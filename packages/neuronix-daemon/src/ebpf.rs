// ==============================================================================
// NEURONIX Declarative eBPF LSM Security Policy Engine
// Synthesizes dynamic syscall restrictions from Nix derivation dependency graphs.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::fs;

#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)]
/// Operating mode for eBPF Linux Security Module policy engine.
pub enum LsmMode {
    Enforcing,
    Audit,
    Disabled,
}

/// eBPF LSM security policy engine for declarative syscall restriction.
///
/// Probes kernel BPF LSM support and generates JSON policy contracts
/// for package-level security enforcement.
pub struct EbpfLsmEngine {
    pub mode: LsmMode,
    pub bpf_lsm_supported: bool,
}

impl EbpfLsmEngine {
    /// Probes the kernel for BPF LSM support via `/sys/kernel/security/lsm`.
    pub fn probe() -> Self {
        let mut bpf_lsm_supported = false;
        if let Ok(lsm) = fs::read_to_string("/sys/kernel/security/lsm") {
            bpf_lsm_supported = lsm.contains("bpf");
        }

        let mode = if bpf_lsm_supported {
            LsmMode::Enforcing
        } else {
            LsmMode::Audit
        };

        EbpfLsmEngine {
            mode,
            bpf_lsm_supported,
        }
    }

    /// Generates a JSON policy contract for a package with allowed filesystem paths.
    pub fn generate_policy_contract(&self, package_name: &str, allowed_paths: &[&str]) -> String {
        let paths_json = allowed_paths.iter()
            .map(|p| format!("\"{}\"", p))
            .collect::<Vec<_>>()
            .join(",");

        format!(
            r#"{{"package":"{}","ebpf_lsm_supported":{},"mode":"{:?}","enforced_paths":[{}],"policy":"RESTRICT_UNAUTHORIZED_SYSCALLS"}}"#,
            package_name,
            self.bpf_lsm_supported,
            self.mode,
            paths_json
        )
    }
}
