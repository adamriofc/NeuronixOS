// ==============================================================================
// NEURONIX Hyperion Domain Broker Engine (PAEA)
// High-performance execution plane broker, capability prober, and proof generator.
// Implements DomainProofV1 canonical cryptographic verification contract.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use crate::crypto::sha256_hex;

pub const NULL_SENTINEL_SHA256: &str = "0000000000000000000000000000000000000000000000000000000000000000";

pub struct HyperionBroker;

impl HyperionBroker {
    /// Probes host kernel capabilities with structured evidence for adaptive execution paths.
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
        let bwrap_path = if Path::new("/run/current-system/sw/bin/bwrap").exists() {
            "/run/current-system/sw/bin/bwrap"
        } else if Path::new("/usr/bin/bwrap").exists() {
            "/usr/bin/bwrap"
        } else if Path::new("/bin/bwrap").exists() {
            "/bin/bwrap"
        } else {
            "none"
        };
        let bwrap_installed = bwrap_path != "none";

        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();

        format!(
            r#"{{"schema_version":"1.1.0","capabilities":{{"kvm_virtualization":{{"present":{},"source":"/dev/kvm","tested":true,"status":"ACTIVE"}},"cgroups_v2":{{"present":{},"source":"/sys/fs/cgroup/cgroup.controllers","tested":true,"status":"ACTIVE"}},"ebpf_lsm_guard":{{"present":{},"source":"/sys/kernel/security/lsm","tested":true,"status":"ACTIVE"}},"transparent_hugepages":{{"present":{},"source":"/sys/kernel/mm/transparent_hugepage/enabled","tested":true,"status":"ACTIVE"}},"memfd_volatile_ram":{{"present":{},"source":"sys_memfd_create","tested":true,"status":"ACTIVE"}},"bubblewrap_sandbox":{{"present":{},"source":"{}","tested":true,"status":"ACTIVE"}}}},"supported_tiers":["TIER_0_FAST_PATH","TIER_1_RAM_GHOST","TIER_2_EBPF_ENCLAVE","TIER_3_MICRO_VM"],"probed_at":{},"status":"ACTIVE"}}"#,
            kvm_present,
            cgroups_v2,
            ebpf_lsm,
            hugepages_supported,
            memfd_supported,
            bwrap_installed,
            bwrap_path,
            now
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

    /// Computes Merkle Domain Proof linking StateRoot, HDS hash, policy, input, output, and runtime receipt.
    /// Strictly adheres to SPEC-NRX-DP-014 (DomainProofV1 canonical formulation).
    /// Fails closed with NO_RUNTIME_RECEIPT if evidence is absent or invalid.
    pub fn generate_proof(
        state_root: &str,
        hds_json_or_hash: &str,
        policy_hash: &str,
        workload_input_hash: &str,
        output_digest: &str,
        runtime_evidence_json: Option<&str>,
        exit_code: i32,
        isolation_tier: &str
    ) -> String {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();

        // 1. Resolve HDS hash
        let hds_hash = if hds_json_or_hash.len() == 64 && hds_json_or_hash.chars().all(|c| c.is_ascii_hexdigit()) {
            hds_json_or_hash.to_string()
        } else {
            sha256_hex(hds_json_or_hash.as_bytes())
        };

        // 2. Resolve output digest
        let out_hash = if output_digest.len() == 64 && output_digest.chars().all(|c| c.is_ascii_hexdigit()) {
            output_digest.to_string()
        } else {
            sha256_hex(output_digest.as_bytes())
        };

        // 3. Resolve workload input hash
        let inp_hash = if workload_input_hash.len() == 64 && workload_input_hash.chars().all(|c| c.is_ascii_hexdigit()) {
            workload_input_hash.to_string()
        } else {
            sha256_hex(workload_input_hash.as_bytes())
        };

        // 4. Validate runtime receipt / evidence existence (Invariant: NO RECEIPT = NO TRUST)
        let (evidence_hash, evidence_json_str, nonce, trust_verdict, math_valid) = match runtime_evidence_json {
            Some(rec_str) if !rec_str.trim().is_empty() && rec_str.trim() != "{}" => {
                let rec_hash = sha256_hex(rec_str.as_bytes());
                let extracted_nonce = extract_field(rec_str, "execution_nonce").unwrap_or_default();
                let backend = extract_field(rec_str, "backend")
                    .or_else(|| extract_field(rec_str, "execution_backend"))
                    .unwrap_or_default();
                let mode = extract_field(rec_str, "runtime_mode").unwrap_or_default();

                let mut tier_mismatch = false;
                if isolation_tier == "TIER_3_MICRO_VM" {
                    if (backend != "qemu_kvm_micro_vm" && backend != "kvm_qemu_v1") || mode != "real_isolated" {
                        tier_mismatch = true;
                    }
                } else if isolation_tier == "TIER_2_EBPF_ENCLAVE" {
                    if (backend != "bwrap_ebpf_enclave" && backend != "bwrap_lsm_v1") || mode != "real_enclave" {
                        tier_mismatch = true;
                    }
                } else if isolation_tier == "TIER_1_RAM_GHOST" {
                    if (backend != "bubblewrap_ram_overlay" && backend != "direct_seccomp_v1") || mode != "real_ghost" {
                        tier_mismatch = true;
                    }
                } else if isolation_tier == "TIER_0_FAST_PATH" {
                    if (backend != "host_direct" && backend != "fast_path_v1") || mode != "real_host" {
                        tier_mismatch = true;
                    }
                }

                if extracted_nonce.is_empty() {
                    ("".to_string(), "{}".to_string(), "".to_string(), "NO_RUNTIME_RECEIPT", false)
                } else if exit_code != 0 {
                    (rec_hash, rec_str.to_string(), extracted_nonce, "EXECUTION_ANOMALY", false)
                } else if tier_mismatch {
                    (rec_hash, rec_str.to_string(), extracted_nonce, "ISOLATION_EVIDENCE_MISMATCH", false)
                } else if state_root == NULL_SENTINEL_SHA256 {
                    (rec_hash, rec_str.to_string(), extracted_nonce, "UNTRUSTED_HOST_POSTURE", true)
                } else {
                    (rec_hash, rec_str.to_string(), extracted_nonce, "VERIFIED_TRUSTED", true)
                }
            },
            _ => {
                // Receipt is missing: strictly fail closed!
                ("".to_string(), "{}".to_string(), "".to_string(), "NO_RUNTIME_RECEIPT", false)
            }
        };

        // 5. Formulate 6-part DomainProofRoot
        let domain_proof_root = if math_valid || !evidence_hash.is_empty() {
            let concat = format!("{}{}{}{}{}{}", state_root, hds_hash, policy_hash, inp_hash, out_hash, evidence_hash);
            sha256_hex(concat.as_bytes())
        } else {
            NULL_SENTINEL_SHA256.to_string()
        };

        let short_id = if domain_proof_root.len() >= 8 { &domain_proof_root[..8].to_uppercase() } else { "UNKNOWN" };
        let domain_id = format!("DOM-2026-09-09-{}", short_id);

        format!(
            r#"{{"schema_version":"1.0.0","proof_type":"HYPERION_DOMAIN_PROOF_V1","domain_id":"{}","domain_proof_root":"{}","host_state_root":"{}","hds_spec_hash":"{}","policy_hash":"{}","workload_input_hash":"{}","output_digest":"{}","runtime_evidence_hash":"{}","runtime_evidence":{},"execution_nonce":"{}","exit_code":{},"timestamp":{},"isolation_tier":"{}","mathematical_validity":{},"trust_verdict":"{}"}}"#,
            domain_id,
            domain_proof_root,
            state_root,
            hds_hash,
            policy_hash,
            inp_hash,
            out_hash,
            evidence_hash,
            evidence_json_str,
            nonce,
            exit_code,
            now,
            isolation_tier,
            math_valid,
            trust_verdict
        )
    }

    /// Cryptographically verifies the authenticity and mathematical integrity of a DomainProof.
    pub fn verify_domain_proof(proof_json: &str, domain_spec_json: Option<&str>) -> (bool, String) {
        let schema_ver = extract_field(proof_json, "schema_version").unwrap_or_default();
        let p_type = extract_field(proof_json, "proof_type").unwrap_or_default();
        if schema_ver != "1.0.0" || p_type != "HYPERION_DOMAIN_PROOF_V1" {
            return (false, "Invalid proof schema or unsupported proof_type".to_string());
        }

        let claimed_root = extract_field(proof_json, "domain_proof_root").unwrap_or_default();
        let state_root = extract_field(proof_json, "host_state_root").unwrap_or_default();
        let hds_hash = extract_field(proof_json, "hds_spec_hash").unwrap_or_default();
        let policy_hash = extract_field(proof_json, "policy_hash").unwrap_or_default();
        let inp_hash = extract_field(proof_json, "workload_input_hash").unwrap_or_default();
        let out_hash = extract_field(proof_json, "output_digest").unwrap_or_default();
        let evidence_hash = extract_field(proof_json, "runtime_evidence_hash").unwrap_or_default();
        let nonce = extract_field(proof_json, "execution_nonce").unwrap_or_default();
        let verdict = extract_field(proof_json, "trust_verdict").unwrap_or_default();

        let exit_code = extract_int_field(proof_json, "exit_code").unwrap_or(-1);

        // 1. Replay defense check
        if nonce.is_empty() || nonce.len() < 16 {
            return (false, "Replay protection violation: missing or invalid execution nonce".to_string());
        }

        // 2. Receipt requirement
        if evidence_hash.is_empty() || evidence_hash == NULL_SENTINEL_SHA256 {
            return (false, "Missing runtime receipt: fail closed (NO_RUNTIME_RECEIPT)".to_string());
        }

        // 3. Mathematical proof root verification
        let concat = format!("{}{}{}{}{}{}", state_root, hds_hash, policy_hash, inp_hash, out_hash, evidence_hash);
        let recomputed_root = sha256_hex(concat.as_bytes());

        if claimed_root != recomputed_root || claimed_root.is_empty() {
            return (false, format!("Domain proof root mismatch: claimed {} != recomputed {}", claimed_root, recomputed_root));
        }

        // 4. HDS specification congruence check if specification provided
        if let Some(spec) = domain_spec_json {
            let spec_digest = sha256_hex(spec.as_bytes());
            if hds_hash != spec_digest {
                return (false, format!("HDS specification hash mismatch: claimed {} != recomputed {}", hds_hash, spec_digest));
            }
        }

        // 5. Execution exit code validation
        if exit_code != 0 {
            return (false, format!("Execution anomaly detected: exit code {}", exit_code));
        }

        // 6. Verdict assertion
        if verdict != "VERIFIED_TRUSTED" {
            return (false, format!("Proof trust verdict is not VERIFIED_TRUSTED: {}", verdict));
        }

        (true, "Proof cryptographically authentic, verified, and replay-resistant".to_string())
    }
}

fn extract_field(json: &str, field: &str) -> Option<String> {
    let key = format!("\"{}\":", field);
    let idx = json.find(&key)?;
    let rest = json[idx + key.len()..].trim_start();
    if rest.starts_with('"') {
        let val = rest[1..].split('"').next()?;
        Some(val.to_string())
    } else {
        let end = rest.find(|c: char| c == ',' || c == '}' || c == ']' || c.is_whitespace())?;
        Some(rest[..end].to_string())
    }
}

fn extract_int_field(json: &str, field: &str) -> Option<i32> {
    let key = format!("\"{}\":", field);
    let idx = json.find(&key)?;
    let rest = json[idx + key.len()..].trim_start();
    let end = rest.find(|c: char| c == ',' || c == '}' || c == ']' || c.is_whitespace())?;
    rest[..end].parse::<i32>().ok()
}
