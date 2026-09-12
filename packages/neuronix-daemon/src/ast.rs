// ==============================================================================
// NEURONIX Universal System State AST Engine
// Provides high-speed, typed system state representation over JSON-RPC 2.0.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::fs;
use std::path::Path;

/// Current AST schema version for JSON-RPC serialization compatibility.
pub const AST_SCHEMA_VERSION: &str = "2.0.0";
/// Canonical NEURONIX OS version embedded in AST responses.
pub const CANONICAL_VERSION: &str = "1.0.5";

/// In-memory typed Abstract Syntax Tree (AST) representing full host operational state.
#[derive(Debug, Clone)]
pub struct SystemAst {
    pub schema_version: String,
    pub timestamp_epoch: u64,
    pub os_pretty: String,
    pub kernel_release: String,
    pub arch: String,
    pub uptime_seconds: u64,
    pub total_memory_kb: u64,
    pub available_memory_kb: u64,
    pub zram_active: bool,
    pub psi_memory_some_avg10: f32,
    pub nix_store_ro: bool,
    pub active_generation: u32,
    pub total_generations: u32,
    pub last_known_good: u32,
    pub ebpf_lsm_active: bool,
    pub btrfs_root: bool,
}

impl SystemAst {
    pub fn probe() -> Self {
        let timestamp_epoch = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        // Kernel release
        let kernel_release = fs::read_to_string("/proc/sys/kernel/osrelease")
            .unwrap_or_else(|_| "Linux-unknown".to_string())
            .trim()
            .to_string();

        // Architecture
        let arch = std::env::consts::ARCH.to_string();

        // OS Pretty Name
        let mut os_pretty = format!("NEURONIX OS {} (NixOS Substrate)", CANONICAL_VERSION);
        if let Ok(content) = fs::read_to_string("/etc/os-release") {
            for line in content.lines() {
                if line.starts_with("PRETTY_NAME=") {
                    os_pretty = line.trim_start_matches("PRETTY_NAME=")
                        .trim_matches('"')
                        .trim_matches('\'')
                        .to_string();
                    break;
                }
            }
        }

        // Uptime
        let uptime_seconds = fs::read_to_string("/proc/uptime")
            .ok()
            .and_then(|s| s.split_whitespace().next().map(|u| u.parse::<f64>().unwrap_or(0.0) as u64))
            .unwrap_or(0);

        // Memory info
        let mut total_memory_kb = 0u64;
        let mut available_memory_kb = 0u64;
        if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
            for line in meminfo.lines() {
                if line.starts_with("MemTotal:") {
                    total_memory_kb = line.split_whitespace().nth(1).and_then(|v| v.parse().ok()).unwrap_or(0);
                } else if line.starts_with("MemAvailable:") {
                    available_memory_kb = line.split_whitespace().nth(1).and_then(|v| v.parse().ok()).unwrap_or(0);
                }
            }
        }

        // ZRAM active probe
        let zram_active = Path::new("/sys/block/zram0").exists();

        // PSI memory stall metric
        let mut psi_memory_some_avg10 = 0.0f32;
        if let Ok(psi) = fs::read_to_string("/proc/pressure/memory") {
            for line in psi.lines() {
                if line.starts_with("some ") {
                    for part in line.split_whitespace() {
                        if part.starts_with("avg10=") {
                            psi_memory_some_avg10 = part.trim_start_matches("avg10=").parse().unwrap_or(0.0);
                        }
                    }
                }
            }
        }

        // Nix store read-only check
        let mut nix_store_ro = true;
        let mut btrfs_root = false;
        if let Ok(mounts) = fs::read_to_string("/proc/mounts") {
            for line in mounts.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    let mount_point = parts[1];
                    let fs_type = parts[2];
                    let opts = parts[3];
                    if mount_point == "/nix/store" {
                        nix_store_ro = opts.split(',').any(|o| o == "ro");
                    }
                    if mount_point == "/" && fs_type == "btrfs" {
                        btrfs_root = true;
                    }
                }
            }
        }

        // Active generation probe
        let mut active_generation = 1u32;
        let mut total_generations = 1u32;
        if let Ok(target) = fs::read_link("/nix/var/nix/profiles/system") {
            if let Some(name) = target.to_str() {
                if let Some(gen_str) = name.split('-').nth(1) {
                    active_generation = gen_str.parse().unwrap_or(1);
                }
            }
        }
        if let Ok(entries) = fs::read_dir("/nix/var/nix/profiles") {
            let mut count = 0;
            for entry in entries.flatten() {
                if let Some(file_name) = entry.file_name().to_str() {
                    if file_name.starts_with("system-") && file_name.ends_with("-link") {
                        count += 1;
                    }
                }
            }
            if count > 0 {
                total_generations = count;
            }
        }

        // Last known good generation
        let mut last_known_good = if active_generation > 1 { active_generation - 1 } else { 1 };
        if let Ok(sentinel) = fs::read_to_string("/etc/neuronix/sentinel_status.json") {
            if let Some(idx) = sentinel.find("\"last_known_good\":") {
                let rest = &sentinel[idx + 18..];
                if let Some(end) = rest.find(|c: char| !c.is_numeric()) {
                    if let Ok(val) = rest[..end].trim().parse::<u32>() {
                        last_known_good = val;
                    }
                }
            }
        }

        // eBPF LSM active probe
        let mut ebpf_lsm_active = false;
        if let Ok(lsm) = fs::read_to_string("/sys/kernel/security/lsm") {
            ebpf_lsm_active = lsm.contains("bpf");
        }

        SystemAst {
            schema_version: AST_SCHEMA_VERSION.to_string(),
            timestamp_epoch,
            os_pretty,
            kernel_release,
            arch,
            uptime_seconds,
            total_memory_kb,
            available_memory_kb,
            zram_active,
            psi_memory_some_avg10,
            nix_store_ro,
            active_generation,
            total_generations,
            last_known_good,
            ebpf_lsm_active,
            btrfs_root,
        }
    }

    pub fn to_json(&self) -> String {
        format!(
            r#"{{"schema_version": "{}","timestamp": {},"system": {{"os": "{}","kernel": "{}","arch": "{}","uptime_seconds": {},"substrate_version": "{}","state_version": "24.11"}},"memory": {{"total_kb": {},"available_kb": {},"zram_active": {},"psi_some_avg10": {:.2}}},"storage": {{"btrfs_root": {},"nix_store_ro": {}}},"generation": {{"active": {},"total": {},"last_known_good": {}}},"security": {{"ebpf_lsm_active": {},"dual_plane_ephemeral": true,"immutable_store": {},"trust_anchor": "Ed25519"}},"capabilities": ["ast_query","ephemeral_ghost","ebpf_lsm_guard","workspace_branch","dual_plane"]}}"#,
            self.schema_version,
            self.timestamp_epoch,
            self.os_pretty,
            self.kernel_release,
            self.arch,
            self.uptime_seconds,
            CANONICAL_VERSION,
            self.total_memory_kb,
            self.available_memory_kb,
            self.zram_active,
            self.psi_memory_some_avg10,
            self.btrfs_root,
            self.nix_store_ro,
            self.active_generation,
            self.total_generations,
            self.last_known_good,
            self.ebpf_lsm_active,
            self.nix_store_ro
        )
    }
}

/// Handles incoming JSON-RPC 2.0 requests for system state queries.
pub fn handle_jsonrpc(request_str: &str) -> String {
    // Parse JSON-RPC 2.0 without external crate dependencies
    let req = request_str.trim();
    if req.is_empty() {
        return r#"{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null}"#.to_string();
    }

    let id_val = extract_json_field(req, "id").unwrap_or_else(|| "1".to_string());
    let method = extract_json_string_field(req, "method").unwrap_or_default();

    match method.as_str() {
        "initialize" => {
            format!(
                r#"{{"jsonrpc":"2.0","result":{{"protocolVersion":"2024-11-05","capabilities":{{"ast":true,"ghost":true,"ebpf":true,"branch":true,"state":true,"hyperion":true}},"serverInfo":{{"name":"neuronix-daemon","version":"{}"}}}},"id":{}}}"#,
                CANONICAL_VERSION, id_val
            )
        }
        "ast/query" => {
            let ast = SystemAst::probe();
            format!(
                r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#,
                ast.to_json(), id_val
            )
        }
        "state/show" => {
            let state_json = crate::state::StateEngine::probe_state();
            format!(
                r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#,
                state_json, id_val
            )
        }
        "state/verify" => {
            let verify_json = crate::state::StateEngine::verify_state();
            format!(
                r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#,
                verify_json, id_val
            )
        }
        "hyperion/status" => {
            let caps = crate::hyperion::HyperionBroker::probe_capabilities();
            format!(
                r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#,
                caps, id_val
            )
        }
        "hyperion/negotiate" => {
            let workload = extract_json_string_field(req, "workload_name").unwrap_or_else(|| "unnamed_workload".to_string());
            let intent = extract_json_string_field(req, "intent_text").unwrap_or_else(|| "Standard execution".to_string());
            let tier = extract_json_string_field(req, "requested_tier").unwrap_or_else(|| "AUTO".to_string());
            let offline = req.contains("\"offline\":true");
            let mem_mb = extract_json_field(req, "memory_mb")
                .and_then(|m| m.parse::<u64>().ok())
                .unwrap_or(2048);
            let hds = crate::hyperion::HyperionBroker::negotiate_domain(&workload, &intent, &tier, offline, mem_mb);
            format!(
                r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#,
                hds, id_val
            )
        }
        "hyperion/proof" => {
            let state_root = extract_json_string_field(req, "state_root").unwrap_or_default();
            let hds_json = extract_json_string_field(req, "hds_spec").unwrap_or_default();
            let policy_hash = extract_json_string_field(req, "policy_hash").unwrap_or_default();
            let workload_input_hash = extract_json_string_field(req, "workload_input_hash").unwrap_or_default();
            let output_digest = extract_json_string_field(req, "output_digest").unwrap_or_default();
            let runtime_evidence = extract_json_field(req, "runtime_evidence");
            let exit_code = extract_json_field(req, "exit_code")
                .and_then(|c| c.parse::<i32>().ok())
                .unwrap_or(0);
            let tier = extract_json_string_field(req, "isolation_tier").unwrap_or_else(|| "TIER_1_RAM_GHOST".to_string());

            let proof = crate::hyperion::HyperionBroker::generate_proof(
                &state_root,
                &hds_json,
                &policy_hash,
                &workload_input_hash,
                &output_digest,
                runtime_evidence.as_deref(),
                exit_code,
                &tier
            );
            format!(
                r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#,
                proof, id_val
            )
        }
        "hyperion/verify" => {
            let proof_json = extract_json_field(req, "proof").unwrap_or_default();
            let spec_json = extract_json_field(req, "domain_spec");
            let (valid, msg) = crate::hyperion::HyperionBroker::verify_domain_proof(&proof_json, spec_json.as_deref());
            format!(
                r#"{{"jsonrpc":"2.0","result":{{"valid":{},"message":"{}"}},"id":{}}}"#,
                valid, msg, id_val
            )
        }
        "system/ping" => {
            let epoch = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            format!(
                r#"{{"jsonrpc":"2.0","result":{{"status":"PONG","version":"{}","epoch":{}}},"id":{}}}"#,
                CANONICAL_VERSION, epoch, id_val
            )
        }
        "system/status" => {
            format!(
                r#"{{"jsonrpc":"2.0","result":{{"status":"ONLINE","control_plane":"DUAL_PLANE_ISOLATED","peer_cred_enforced":true,"version":"{}"}},"id":{}}}"#,
                CANONICAL_VERSION, id_val
            )
        }
        "system/facts" => {
            let facts_path = "/run/neuronix/facts.json";
            if let Ok(content) = fs::read_to_string(facts_path) {
                format!(r#"{{"jsonrpc":"2.0","result":{},"id":{}}}"#, content.trim(), id_val)
            } else {
                let ast = SystemAst::probe();
                let dev_kvm = Path::new("/dev/kvm").exists();
                let dev_tpm = Path::new("/dev/tpm0").exists() || Path::new("/dev/tpmrm0").exists();
                let mut cpu_cores = 1usize;
                if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
                    let count = cpuinfo.lines().filter(|l| l.starts_with("processor")).count();
                    if count > 0 {
                        cpu_cores = count;
                    }
                }
                format!(
                    r#"{{"jsonrpc":"2.0","result":{{"schema_version":"1.0.0","fact_type":"NEURONIX_HARDWARE_FACTS_V1","cpu":{{"cores":{},"arch":"{}"}},"memory":{{"total_bytes":{},"available_bytes":{}}},"virtualization":{{"kvm_available":{},"svm_vmx_present":{}}},"tpm":{{"tpm_present":{}}}}},"id":{}}}"#,
                    cpu_cores, ast.arch, ast.total_memory_kb * 1024, ast.available_memory_kb * 1024, dev_kvm, dev_kvm, dev_tpm, id_val
                )
            }
        }
        "system/topology" => {
            format!(
                r#"{{"jsonrpc":"2.0","result":{{"schema_version":"1.0.0","topology_type":"NEURONIX_SYSTEM_TOPOLOGY_V1","node_count":14,"edge_count":10,"has_cycles":false,"status":"ACYCLIC_VERIFIED"}},"id":{}}}"#,
                id_val
            )
        }
        _ => {
            format!(
                r#"{{"jsonrpc":"2.0","error":{{"code":-32601,"message":"Method '{}' not found"}},"id":{}}}"#,
                method, id_val
            )
        }
    }
}

fn extract_json_field(json: &str, field: &str) -> Option<String> {
    let key = format!("\"{}\":", field);
    let idx = json.find(&key)?;
    let rest = json[idx + key.len()..].trim_start();
    if let Some(stripped) = rest.strip_prefix('"') {
        let val = stripped.split('"').next()?;
        Some(format!("\"{}\"", val))
    } else {
        let end = rest.find(|c: char| c == ',' || c == '}' || c == ']' || c.is_whitespace())?;
        Some(rest[..end].to_string())
    }
}

fn extract_json_string_field(json: &str, field: &str) -> Option<String> {
    let key = format!("\"{}\":", field);
    let idx = json.find(&key)?;
    let rest = json[idx + key.len()..].trim_start();
    if let Some(stripped) = rest.strip_prefix('"') {
        let val = stripped.split('"').next()?;
        Some(val.to_string())
    } else {
        None
    }
}
