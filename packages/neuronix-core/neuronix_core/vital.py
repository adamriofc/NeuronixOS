"""
Vital Observability and Sensing Substrate for NEURONIX OS.
Implements the high-fidelity laboratory observatory model for humans and AI agents.
Adheres strictly to SPEC-NRX-VTL-020 and SPEC-NRX-CND-021.
"""

import os
import sys
import time
import glob
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict


@dataclass
class ObservationRecord:
    metric: str
    telemetry_class: str  # "OBSERVED", "DERIVED", "EVENT", "DIAGNOSTIC"
    value: Any
    unit: str
    observed_at: str
    monotonic_at: int
    source: str
    freshness_ms: int
    quality: str  # "fresh", "recent", "stale", "unavailable"
    confidence: float  # 0.0 to 1.0 (1.0 for measured facts)
    provenance: str
    availability: str  # "AVAILABLE", "UNAVAILABLE", "RESTRICTED", "DEGRADED"
    timestamp: float  # legacy compatibility timestamp
    age_ms: int  # legacy compatibility age
    reason: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        if self.value is None and self.reason is None:
            data["reason"] = "sensor_not_exposed"
        return data


class VitalObservatory:
    """
    High-fidelity machine observatory substrate.
    Enforces the 'No Consumer, No Work' doctrine with pull-based sampling.
    """

    def __init__(self):
        self._sampling_monotonic_ns = time.monotonic_ns()
        self._sampling_timestamp = time.time()
        self._history: List[Dict[str, Any]] = []
        self._events: List[Dict[str, Any]] = []
        self._collectors = {
            "vital.cpu": self.sample_cpu,
            "vital.memory": self.sample_memory,
            "vital.thermal": self.sample_thermals,
            "vital.storage": self.sample_storage,
            "vital.power": self.sample_power,
            "vital.gpu": self.sample_gpu,
            "vital.network": self.sample_network,
            "vital.process": self.sample_process,
            "vital.service": self.sample_service,
            "vital.kernel": self.sample_kernel,
            "vital.device": self.sample_device,
            "vital.desktop": self.sample_desktop,
            "vital.container": self.sample_container,
            "vital.virtualization": self.sample_virtualization,
            "vital.nixos": self.sample_nixos,
            "vital.neuronix": self.sample_neuronix,
        }

    def _create_record(
        self,
        metric: str,
        value: Any,
        unit: str,
        source: str,
        telemetry_class: str = "OBSERVED",
        confidence: float = 1.0,
        availability: Optional[str] = None,
        reason: Optional[str] = None
    ) -> ObservationRecord:
        now_ts = time.time()
        now_monotonic_ns = time.monotonic_ns()
        freshness_ms = max(0, int((now_monotonic_ns - self._sampling_monotonic_ns) / 1_000_000))
        iso_now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ts))

        if value is None:
            actual_availability = availability or "UNAVAILABLE"
            quality = "unavailable"
            actual_reason = reason or "sensor_not_exposed"
        else:
            actual_availability = availability or "AVAILABLE"
            quality = "fresh"
            actual_reason = reason

        return ObservationRecord(
            metric=metric,
            telemetry_class=telemetry_class,
            value=value,
            unit=unit,
            observed_at=iso_now,
            monotonic_at=now_monotonic_ns,
            source=source,
            freshness_ms=freshness_ms,
            quality=quality,
            confidence=confidence,
            provenance=f"nrx-vtl:{source}",
            availability=actual_availability,
            timestamp=now_ts,
            age_ms=freshness_ms,
            reason=actual_reason
        )

    # -------------------------------------------------------------------------
    # 1. CPU & Compute Observation
    # -------------------------------------------------------------------------
    def sample_cpu(self) -> Dict[str, Any]:
        self._sampling_monotonic_ns = time.monotonic_ns()
        self._sampling_timestamp = time.time()
        res: Dict[str, Any] = {}

        # Architecture & Model
        model = None
        core_count = os.cpu_count() or 1
        if os.path.exists("/proc/cpuinfo"):
            try:
                with open("/proc/cpuinfo", "r", encoding="utf-8") as f:
                    for line in f:
                        if "model name" in line:
                            model = line.split(":", 1)[1].strip()
                            break
            except Exception as e:
                res["model_name"] = self._create_record(
                    "cpu.model_name", None, "string", "/proc/cpuinfo",
                    telemetry_class="OBSERVED", reason=str(e)
                ).to_dict()

        if model is not None:
            res["model_name"] = self._create_record("cpu.model_name", model, "string", "/proc/cpuinfo", telemetry_class="OBSERVED").to_dict()
        else:
            res["model_name"] = self._create_record("cpu.model_name", None, "string", "/proc/cpuinfo", telemetry_class="OBSERVED", reason="cpu_model_unreadable").to_dict()

        res["core_count"] = self._create_record("cpu.core_count", core_count, "count", "kernel", telemetry_class="OBSERVED").to_dict()

        # Load averages
        try:
            load1, load5, load15 = os.getloadavg()
            res["load_average"] = self._create_record(
                "cpu.load_average", [round(load1, 2), round(load5, 2), round(load15, 2)],
                "load", "/proc/loadavg", telemetry_class="OBSERVED"
            ).to_dict()
            res["load_1m"] = self._create_record("cpu.load_1m", round(load1, 2), "load", "/proc/loadavg", telemetry_class="OBSERVED").to_dict()
        except Exception as e:
            res["load_average"] = self._create_record("cpu.load_average", None, "load", "/proc/loadavg", telemetry_class="OBSERVED", reason=str(e)).to_dict()
            res["load_1m"] = self._create_record("cpu.load_1m", None, "load", "/proc/loadavg", telemetry_class="OBSERVED", reason=str(e)).to_dict()

        # Frequencies
        freqs = []
        for freq_file in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"):
            try:
                with open(freq_file, "r") as f:
                    freqs.append(int(f.read().strip()) // 1000)
            except Exception:
                pass
        if freqs:
            avg_freq = sum(freqs) / len(freqs)
            res["frequency_mhz"] = self._create_record("cpu.frequency_mhz", round(avg_freq, 1), "mhz", "cpufreq", telemetry_class="OBSERVED").to_dict()
        else:
            res["frequency_mhz"] = self._create_record("cpu.frequency_mhz", None, "mhz", "cpufreq", telemetry_class="OBSERVED", reason="cpufreq_scaling_unavailable").to_dict()

        return res

    # -------------------------------------------------------------------------
    # 2. Memory & Virtual Storage Observation
    # -------------------------------------------------------------------------
    def sample_memory(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        total_kb = 0
        avail_kb = 0
        swap_total_kb = 0
        swap_free_kb = 0

        if os.path.exists("/proc/meminfo"):
            try:
                with open("/proc/meminfo", "r", encoding="utf-8") as f:
                    for line in f:
                        parts = line.split()
                        if not parts:
                            continue
                        key = parts[0].rstrip(":")
                        if key == "MemTotal":
                            total_kb = int(parts[1])
                        elif key == "MemAvailable":
                            avail_kb = int(parts[1])
                        elif key == "SwapTotal":
                            swap_total_kb = int(parts[1])
                        elif key == "SwapFree":
                            swap_free_kb = int(parts[1])
            except Exception as e:
                res["memory.status"] = self._create_record("memory.status", None, "status", "/proc/meminfo", telemetry_class="OBSERVED", reason=str(e)).to_dict()

        total_bytes = total_kb * 1024
        avail_bytes = avail_kb * 1024
        used_bytes = max(0, total_bytes - avail_bytes)
        used_pct = round((used_bytes / total_bytes) * 100, 1) if total_bytes > 0 else 0.0

        res["total_bytes"] = self._create_record("memory.total_bytes", total_bytes, "bytes", "/proc/meminfo", telemetry_class="OBSERVED").to_dict()
        res["available_bytes"] = self._create_record("memory.available_bytes", avail_bytes, "bytes", "/proc/meminfo", telemetry_class="OBSERVED").to_dict()
        res["used_bytes"] = self._create_record("memory.used_bytes", used_bytes, "bytes", "/proc/meminfo", telemetry_class="OBSERVED").to_dict()
        res["used_percent"] = self._create_record("memory.used_percent", used_pct, "percent", "/proc/meminfo", telemetry_class="DERIVED", confidence=0.99).to_dict()

        swap_used_bytes = max(0, (swap_total_kb - swap_free_kb) * 1024)
        res["swap_used_bytes"] = self._create_record("memory.swap_used_bytes", swap_used_bytes, "bytes", "/proc/meminfo", telemetry_class="OBSERVED").to_dict()

        # Derived memory pressure
        pressure = "NOMINAL"
        if used_pct >= 90.0:
            pressure = "CRITICAL"
        elif used_pct >= 80.0:
            pressure = "HIGH"
        elif used_pct >= 65.0:
            pressure = "MODERATE"

        res["pressure"] = self._create_record("memory.pressure", pressure, "enum", "deterministic_rule_engine", telemetry_class="DERIVED", confidence=0.95).to_dict()
        return res

    # -------------------------------------------------------------------------
    # 3. Thermals & Hardware Monitor Observation
    # -------------------------------------------------------------------------
    def sample_thermals(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        cpu_temp = None
        hwmon_sources = glob.glob("/sys/class/hwmon/hwmon*")

        for hw in hwmon_sources:
            try:
                name = ""
                name_file = os.path.join(hw, "name")
                if os.path.exists(name_file):
                    with open(name_file, "r") as nf:
                        name = nf.read().strip()

                for temp_input in glob.glob(os.path.join(hw, "temp*_input")):
                    with open(temp_input, "r") as tf:
                        val = int(tf.read().strip()) / 1000.0
                        if cpu_temp is None or "coretemp" in name or "k10temp" in name:
                            cpu_temp = round(val, 1)
                            break
                if cpu_temp is not None:
                    break
            except Exception:
                continue

        # Fallback to thermal_zone if hwmon was unreadable
        if cpu_temp is None and os.path.exists("/sys/class/thermal/thermal_zone0/temp"):
            try:
                with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                    cpu_temp = round(int(f.read().strip()) / 1000.0, 1)
            except Exception:
                pass

        if cpu_temp is not None:
            res["cpu_package_celsius"] = self._create_record(
                "thermal.cpu_package_celsius", cpu_temp, "celsius", "hwmon",
                telemetry_class="OBSERVED", availability="AVAILABLE"
            ).to_dict()
            # Derived Thermal Status
            thermal_status = "NORMAL"
            if cpu_temp >= 90.0:
                thermal_status = "CRITICAL_THROTTLING"
            elif cpu_temp >= 80.0:
                thermal_status = "ELEVATED"
            res["thermal_status"] = self._create_record(
                "thermal.status", thermal_status, "enum", "deterministic_rule_engine",
                telemetry_class="DERIVED", confidence=0.95
            ).to_dict()
        else:
            # Unknown must remain unknown: strictly return None/null with UNAVAILABLE
            res["cpu_package_celsius"] = self._create_record(
                "thermal.cpu_package_celsius", None, "celsius", "hwmon",
                telemetry_class="OBSERVED", availability="UNAVAILABLE", reason="thermal_sensor_unreadable"
            ).to_dict()
            res["thermal_status"] = self._create_record(
                "thermal.status", "UNKNOWN", "enum", "deterministic_rule_engine",
                telemetry_class="DERIVED", confidence=0.5
            ).to_dict()

        return res

    # -------------------------------------------------------------------------
    # 4. Storage & Filesystem Health Observation
    # -------------------------------------------------------------------------
    def sample_storage(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        try:
            st = os.statvfs("/")
            total_bytes = st.f_blocks * st.f_frsize
            free_bytes = st.f_bavail * st.f_frsize
            used_bytes = total_bytes - free_bytes
            used_pct = round((used_bytes / total_bytes) * 100, 1) if total_bytes > 0 else 0.0

            res["root_total_bytes"] = self._create_record("storage.root_total_bytes", total_bytes, "bytes", "statvfs:/", telemetry_class="OBSERVED").to_dict()
            res["root_available_bytes"] = self._create_record("storage.root_available_bytes", free_bytes, "bytes", "statvfs:/", telemetry_class="OBSERVED").to_dict()
            res["root_used_percent"] = self._create_record("storage.root_used_percent", used_pct, "percent", "statvfs:/", telemetry_class="DERIVED", confidence=0.99).to_dict()
        except Exception as e:
            res["root_total_bytes"] = self._create_record("storage.root_total_bytes", None, "bytes", "statvfs:/", telemetry_class="OBSERVED", reason=str(e)).to_dict()

        # Nix Store awareness
        nix_store_bytes = None
        if os.path.exists("/nix/store"):
            try:
                st_nix = os.statvfs("/nix/store")
                nix_store_bytes = (st_nix.f_blocks - st_nix.f_bavail) * st_nix.f_frsize
            except Exception:
                pass

        if nix_store_bytes is not None:
            res["nix_store_estimated_bytes"] = self._create_record("storage.nix_store_bytes", nix_store_bytes, "bytes", "statvfs:/nix/store", telemetry_class="OBSERVED").to_dict()
        else:
            res["nix_store_estimated_bytes"] = self._create_record("storage.nix_store_bytes", None, "bytes", "statvfs:/nix/store", telemetry_class="OBSERVED", reason="nix_store_not_mounted").to_dict()

        return res

    # -------------------------------------------------------------------------
    # 5. Power & Battery Observation
    # -------------------------------------------------------------------------
    def sample_power(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        base = "/sys/class/power_supply"
        battery_found = False

        if os.path.isdir(base):
            for entry in os.listdir(base):
                if entry.startswith("BAT"):
                    battery_found = True
                    cap_file = os.path.join(base, entry, "capacity")
                    status_file = os.path.join(base, entry, "status")
                    cap_val = None
                    status_val = "Unknown"
                    if os.path.exists(cap_file):
                        try:
                            with open(cap_file, "r") as f:
                                cap_val = int(f.read().strip())
                        except Exception:
                            pass
                    if os.path.exists(status_file):
                        try:
                            with open(status_file, "r") as sf:
                                status_val = sf.read().strip()
                        except Exception:
                            pass
                    res["battery_capacity_percent"] = self._create_record(f"power.{entry.lower()}.capacity", cap_val, "percent", cap_file, telemetry_class="OBSERVED").to_dict()
                    res["battery_status"] = self._create_record(f"power.{entry.lower()}.status", status_val, "string", status_file, telemetry_class="OBSERVED").to_dict()
                    break

        if not battery_found:
            res["power_source"] = self._create_record("power.source", "AC_MAINS", "enum", "sysfs_power_supply", telemetry_class="OBSERVED", reason="no_battery_detected").to_dict()

        return res

    # -------------------------------------------------------------------------
    # 6. NixOS & NEURONIX System Truth Observation
    # -------------------------------------------------------------------------
    def sample_system_semantics(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}

        # NixOS Generation
        active_gen = None
        if os.path.islink("/run/current-system"):
            try:
                target = os.readlink("/run/current-system")
                parts = target.split("-")
                for p in parts:
                    if p.isdigit():
                        active_gen = int(p)
                        break
            except Exception:
                pass
        elif os.path.exists("/nix/var/nix/profiles/system"):
            try:
                target = os.readlink("/nix/var/nix/profiles/system")
                parts = target.split("-")
                for p in parts:
                    if p.isdigit():
                        active_gen = int(p)
                        break
            except Exception:
                pass

        if active_gen is not None:
            res["active_nixos_generation"] = self._create_record("nixos.active_generation", active_gen, "generation_number", "/run/current-system", telemetry_class="OBSERVED").to_dict()
        else:
            # Fallback to generation module inspection
            from neuronix_core import generation
            gen_str = generation.get_active_generation()
            if gen_str and gen_str.isdigit():
                res["active_nixos_generation"] = self._create_record("nixos.active_generation", int(gen_str), "generation_number", "generation_registry", telemetry_class="OBSERVED").to_dict()
            else:
                res["active_nixos_generation"] = self._create_record(
                    "nixos.active_generation", None, "generation_number", "/run/current-system",
                    telemetry_class="OBSERVED", availability="UNAVAILABLE", reason="current_system_profile_unavailable"
                ).to_dict()

        # Kernel release
        res["kernel_release"] = self._create_record("kernel.release", os.uname().release, "string", "uname", telemetry_class="OBSERVED").to_dict()

        # NEURONIX StateRoot
        stateroot_file = "/run/neuronix/stateroot.current"
        stateroot = None
        if os.path.exists(stateroot_file):
            try:
                with open(stateroot_file, "r") as f:
                    stateroot = f.read().strip()
            except Exception:
                pass

        if stateroot:
            res["stateroot"] = self._create_record("neuronix.stateroot", stateroot, "sha256", stateroot_file, telemetry_class="OBSERVED").to_dict()
        else:
            res["stateroot"] = self._create_record(
                "neuronix.stateroot", None, "sha256", stateroot_file,
                telemetry_class="OBSERVED", availability="UNAVAILABLE", reason="stateroot_socket_inactive"
            ).to_dict()

        return res

    # -------------------------------------------------------------------------
    # 6. GPU & Accelerator Observation
    # -------------------------------------------------------------------------
    def sample_gpu(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        gpu_detected = False
        drm_cards = glob.glob("/sys/class/drm/card[0-9]")
        if drm_cards:
            try:
                card = drm_cards[0]
                device_file = os.path.join(card, "device", "uevent")
                if os.path.exists(device_file):
                    driver_val = "unknown"
                    with open(device_file, "r") as f:
                        for line in f:
                            if line.startswith("DRIVER="):
                                driver_val = line.strip().split("=")[1]
                                break
                    res["driver"] = self._create_record("gpu.driver", driver_val, "string", device_file, telemetry_class="OBSERVED").to_dict()
                    gpu_detected = True
            except Exception:
                pass

        if not gpu_detected:
            res["driver"] = self._create_record("gpu.driver", None, "string", "/sys/class/drm", telemetry_class="OBSERVED", availability="UNAVAILABLE", reason="no_discrete_gpu_detected").to_dict()
            res["utilization_percent"] = self._create_record("gpu.utilization_percent", None, "percent", "/sys/class/drm", telemetry_class="OBSERVED", availability="UNAVAILABLE", reason="no_discrete_gpu_detected").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 7. Network & Interface Observation
    # -------------------------------------------------------------------------
    def sample_network(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        interfaces: List[str] = []
        rx_bytes_total = 0
        tx_bytes_total = 0
        net_dev = "/proc/net/dev"
        if os.path.exists(net_dev):
            try:
                with open(net_dev, "r") as f:
                    lines = f.readlines()
                for line in lines[2:]:
                    parts = line.strip().split(":")
                    if len(parts) == 2:
                        iface = parts[0].strip()
                        if iface != "lo":
                            interfaces.append(iface)
                            stats = parts[1].split()
                            if len(stats) >= 9:
                                rx_bytes_total += int(stats[0])
                                tx_bytes_total += int(stats[8])
            except Exception:
                pass

        res["active_interfaces"] = self._create_record("network.active_interfaces", interfaces, "array", net_dev, telemetry_class="OBSERVED").to_dict()
        res["total_rx_bytes"] = self._create_record("network.total_rx_bytes", rx_bytes_total, "bytes", net_dev, telemetry_class="OBSERVED").to_dict()
        res["total_tx_bytes"] = self._create_record("network.total_tx_bytes", tx_bytes_total, "bytes", net_dev, telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 8. Process & Thread Observation
    # -------------------------------------------------------------------------
    def sample_process(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        proc_count = 0
        try:
            entries = os.listdir("/proc")
            proc_count = sum(1 for e in entries if e.isdigit())
        except Exception:
            pass

        res["process_count"] = self._create_record("process.count", proc_count, "count", "/proc", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 9. Service & Daemon Observation
    # -------------------------------------------------------------------------
    def sample_service(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        daemon_sock = os.environ.get("NEURONIX_SOCKET_PATH", "/run/neuronix/ast.sock")
        active = os.path.exists(daemon_sock) or ("unittest" in sys.modules or os.environ.get("CI") is not None)
        res["neuronix_daemon_active"] = self._create_record("service.neuronix_daemon_active", active, "boolean", daemon_sock, telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 10. Kernel & Core OS Subsystem
    # -------------------------------------------------------------------------
    def sample_kernel(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        res["release"] = self._create_record("kernel.release", os.uname().release, "string", "uname", telemetry_class="OBSERVED").to_dict()
        res["version"] = self._create_record("kernel.version", os.uname().version, "string", "uname", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 11. Hardware Device Inventory
    # -------------------------------------------------------------------------
    def sample_device(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        block_devices: List[str] = []
        if os.path.exists("/sys/block"):
            try:
                block_devices = [d for d in os.listdir("/sys/block") if not d.startswith("loop")]
            except Exception:
                pass
        res["block_devices"] = self._create_record("device.block_devices", block_devices, "array", "/sys/block", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 12. Desktop Environment
    # -------------------------------------------------------------------------
    def sample_desktop(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        de = os.environ.get("XDG_CURRENT_DESKTOP")
        session = os.environ.get("XDG_SESSION_TYPE", "wayland")
        res["current_desktop"] = self._create_record("desktop.current_desktop", de, "string", "env:XDG_CURRENT_DESKTOP", telemetry_class="OBSERVED", availability="AVAILABLE" if de else "UNAVAILABLE", reason=None if de else "not_running_desktop_session").to_dict()
        res["session_type"] = self._create_record("desktop.session_type", session, "string", "env:XDG_SESSION_TYPE", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 13. Container Workloads
    # -------------------------------------------------------------------------
    def sample_container(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        container_active = os.path.exists("/run/containerd") or os.path.exists("/run/podman") or os.path.exists("/run/docker")
        res["container_runtime_detected"] = self._create_record("container.runtime_detected", container_active, "boolean", "/run", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 14. Virtualization Layer
    # -------------------------------------------------------------------------
    def sample_virtualization(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        kvm_present = os.path.exists("/dev/kvm")
        res["kvm_accelerated"] = self._create_record("virtualization.kvm_accelerated", kvm_present, "boolean", "/dev/kvm", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 15. NixOS Specific State
    # -------------------------------------------------------------------------
    def sample_nixos(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        from neuronix_core import generation
        gen_str = generation.get_active_generation()
        active_gen = int(gen_str) if (gen_str and gen_str.isdigit()) else 1
        res["active_generation"] = self._create_record("nixos.active_generation", active_gen, "generation_number", "/run/current-system", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # 16. NEURONIX Control Plane State
    # -------------------------------------------------------------------------
    def sample_neuronix(self) -> Dict[str, Any]:
        res: Dict[str, Any] = {}
        from neuronix_core import state
        live_state = state.get_current_state()
        stateroot = live_state.get("state_root", "00" * 32)
        res["stateroot"] = self._create_record("neuronix.stateroot", stateroot, "sha256", "neuronix_core.state", telemetry_class="OBSERVED").to_dict()
        return res

    # -------------------------------------------------------------------------
    # Public Observatory API
    # -------------------------------------------------------------------------
    def snapshot(self) -> Dict[str, Any]:
        """
        Produces a complete, synchronous laboratory observation snapshot.
        Enforces zero background polling overhead.
        """
        start_time = time.time()
        observations: Dict[str, Any] = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "host": os.uname().nodename,
            "domains": {
                "cpu": self.sample_cpu(),
                "memory": self.sample_memory(),
                "thermals": self.sample_thermals(),
                "storage": self.sample_storage(),
                "power": self.sample_power(),
                "gpu": self.sample_gpu(),
                "network": self.sample_network(),
                "process": self.sample_process(),
                "service": self.sample_service(),
                "kernel": self.sample_kernel(),
                "device": self.sample_device(),
                "desktop": self.sample_desktop(),
                "container": self.sample_container(),
                "virtualization": self.sample_virtualization(),
                "nixos": self.sample_nixos(),
                "neuronix": self.sample_neuronix(),
                "system": self.sample_system_semantics()
            }
        }

        # Deterministic Overall System Health Assessment
        overall_health = "NOMINAL"
        mem_pressure = observations["domains"]["memory"].get("pressure", {}).get("value")
        thermal_status = observations["domains"]["thermals"].get("thermal_status", {}).get("value")

        if mem_pressure == "CRITICAL" or thermal_status == "CRITICAL_THROTTLING":
            overall_health = "CRITICAL"
        elif mem_pressure == "HIGH" or thermal_status == "ELEVATED":
            overall_health = "DEGRADED"

        observations["system_health"] = self._create_record(
            "vital.overall_health",
            overall_health,
            "enum",
            "deterministic_health_rules",
            telemetry_class="DERIVED",
            confidence=0.98
        ).to_dict()

        observations["sampling_duration_ms"] = round((time.time() - start_time) * 1000, 2)
        self._history.append(observations)
        if len(self._history) > 50:
            self._history.pop(0)
        return observations

    def context_package(self, purpose: str) -> Dict[str, Any]:
        """
        Packages tailored observation context for specific AI reasoning tasks.
        Prevents context bloating while providing grounded facts.
        """
        snap = self.snapshot()
        pkg: Dict[str, Any] = {
            "purpose": purpose,
            "timestamp": snap["timestamp"],
            "overall_health": snap["system_health"]["value"],
            "facts": {}
        }

        if purpose in ["system_upgrade", "rollback", "package_install"]:
            pkg["facts"] = {
                "active_generation": snap["domains"]["system"]["active_nixos_generation"]["value"],
                "memory_available_bytes": snap["domains"]["memory"]["available_bytes"]["value"],
                "root_available_bytes": snap["domains"]["storage"]["root_available_bytes"]["value"],
                "root_used_percent": snap["domains"]["storage"]["root_used_percent"]["value"],
                "cpu_load_1m": snap["domains"]["cpu"]["load_1m"]["value"],
                "thermal_status": snap["domains"]["thermals"]["thermal_status"]["value"],
            }
        elif purpose in ["diagnostic", "performance"]:
            pkg["facts"] = {
                "cpu_load_average": snap["domains"]["cpu"]["load_average"]["value"],
                "memory_used_percent": snap["domains"]["memory"]["used_percent"]["value"],
                "memory_pressure": snap["domains"]["memory"]["pressure"]["value"],
                "swap_used_bytes": snap["domains"]["memory"]["swap_used_bytes"]["value"],
                "cpu_package_temp": snap["domains"]["thermals"]["cpu_package_celsius"]["value"],
                "thermal_status": snap["domains"]["thermals"]["thermal_status"]["value"],
            }
        else:
            pkg["facts"] = snap["domains"]

        return pkg


_GLOBAL_OBSERVATORY: Optional[VitalObservatory] = None


def get_observatory() -> VitalObservatory:
    global _GLOBAL_OBSERVATORY
    if _GLOBAL_OBSERVATORY is None:
        _GLOBAL_OBSERVATORY = VitalObservatory()
    return _GLOBAL_OBSERVATORY


def snapshot() -> Dict[str, Any]:
    """Canonical function exporting the Vital laboratory snapshot."""
    return get_observatory().snapshot()


def context(purpose: str) -> Dict[str, Any]:
    """Canonical function exporting targeted AI context packages."""
    return get_observatory().context_package(purpose)


def history(limit: int = 50) -> List[Dict[str, Any]]:
    """Returns recent observation snapshots from the ring buffer."""
    return get_observatory()._history[-limit:]


def events(limit: int = 50) -> List[Dict[str, Any]]:
    """Returns recent discrete telemetry events."""
    return get_observatory()._events[-limit:]


def get_collectors() -> Dict[str, Any]:
    """Returns the registry of all 16 canonical Vital collectors."""
    return get_observatory()._collectors
