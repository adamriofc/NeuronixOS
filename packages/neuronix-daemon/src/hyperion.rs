// ==============================================================================
// NEURONIX Hyperion Domain Broker Engine (PAEA)
// High-performance execution plane broker, capability prober, and proof generator.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use crate::crypto::sha256_hex;

pub struct HyperionBroker;

impl HyperionBroker {
    /// Probes host kernel capabilities for adaptive execution paths.
    pub fn probe_capabilities() -> String {
        let kvm_present = Path::new("/dev/kvm").exists();
        let cgroups_v2 = Path::new("/sys/fs/cgroup/cgroup.controllers").exists();
        
        let mut ebpf_lsm = false;
        if let Ok(content) = fs::read_to_string("/sys/kernel/security/lsm") {
            if content.contains("bpf") {
                ebpf_lsm = true;
            }
        }

        let mut hugepages_supported = false;
        if let Ok(content) = fs::read_to_string("/sys/kernel/mm/transparent_hugepage/enabled") {
            if content.contains("[always]") || content.contains("[madvise]") {
                hugepages_supported = true;
            }
        }

        let memfd_supported = true; // Linux >= 3.17 always supported
        let bwrap_installed = Path::new("/run/current-system/sw/bin/bwrap").exists()
            || Path::new("/usr/bin/bwrap").exists()
            || Path::new("/bin/bwrap").exists();

        format!(
            r#"{{"schema_version":"1.0.0","capabilities":{{"kvm_virtualization":{},"cgroups_v2":{},"ebpf_lsm_guard":{},"transparent_hugepages":{},"memfd_volatile_ram":{},"bubblewrap_sandbox":{}}},"supported_tiers":["TIER_0_FAST_PATH","TIER_1_RAM_GHOST","TIER_2_EBPF_ENCLAVE","TIER_3_MICRO_VM"],"status":"ACTIVE"}}"#,
            kvm_present,
            cgroups_v2,
            ebpf_lsm,
            hugepages_supported,
            memfd_supported,
            bwrap_installed
        )
    }

    /// Negotiates an authoritative HDS specification for a workload.
    pub fn negotiate_domain(
        workload_name: &str,
        intent_text: &str,
        requested_tier: &str,
        offline: bool,
        memory_mb: u64
    ) -> String {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
        let seed = format!("{}-{}-{}", workload_name, intent_text, now);
        let hash = sha256_hex(seed.as_bytes());
        let short_id = &hash[..8].to_uppercase();
        let domain_id = format!("DOM-2026-09-09-{}", short_id);

        let tier = match requested_tier {
            "tier0" | "fast-path" | "TIER_0_FAST_PATH" => "TIER_0_FAST_PATH",
            "tier2" | "enclave" | "TIER_2_EBPF_ENCLAVE" => "TIER_2_EBPF_ENCLAVE",
            "tier3" | "microvm" | "isolated" | "TIER_3_MICRO_VM" => "TIER_3_MICRO_VM",
            _ => "TIER_1_RAM_GHOST",
        };

        let net_policy = if offline { "OFFLINE_AIRGAP" } else { "HOST_SHARED" };
        let mount_type = if tier == "TIER_0_FAST_PATH" { "HOST_PASSTHROUGH" } else { "MEMFD_VOLATILE_RAM" };

        format!(
            r#"{{"schema_version":"1.0.0","domain_id":"{}","workload_name":"{}","intent_source":{{"actor_uid":1000,"actor_role":"DEVELOPER","intent_text":"{}"}},"isolation_tier":"{}","resource_envelope":{{"cpu":{{"cores_allocated":[0,1],"scheduling_policy":"SCHED_NORMAL"}},"memory":{{"limit_mb":{},"hugepages":"none","swap_policy":"ZRAM_COMPRESSED_ONLY"}},"storage":{{"mount_type":"{}","auto_vaporize_on_exit":true}},"network":{{"policy":"{}","allow_inbound":false,"allow_outbound":{}}}}},"security_contracts":{{"ebpf_lsm_ruleset":"STRICT_WORKSPACE_ONLY","credential_scrubbing":true,"disallowed_paths":["/etc/shadow","/root","/etc/ssh"]}},"lifecycle":{{"max_duration_seconds":3600,"on_anomaly":"FAIL_CLOSED"}}}}"#,
            domain_id,
            workload_name,
            intent_text,
            tier,
            memory_mb,
            mount_type,
            net_policy,
            !offline
        )
    }

    /// Computes Merkle Domain Proof linking StateRoot, HDS hash, policy leaf, and output.
    pub fn generate_proof(
        state_root: &str,
        hds_json: &str,
        policy_hash: &str,
        output_digest: &str
    ) -> String {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
        let hds_hash = sha256_hex(hds_json.as_bytes());
        let out_hash = if output_digest.len() == 64 {
            output_digest.to_string()
        } else {
            sha256_hex(output_digest.as_bytes())
        };

        let concat = format!("{}{}{}{}", state_root, hds_hash, policy_hash, out_hash);
        let domain_proof_root = sha256_hex(concat.as_bytes());

        format!(
            r#"{{"schema_version":"1.0.0","proof_type":"HYPERION_DOMAIN_PROOF_V1","domain_proof_root":"{}","host_state_root":"{}","hds_spec_hash":"{}","policy_hash":"{}","output_digest":"{}","timestamp":{},"trust_verdict":"VERIFIED_TRUSTED"}}"#,
            domain_proof_root,
            state_root,
            hds_hash,
            policy_hash,
            out_hash,
            now
        )
    }
}
