// ==============================================================================
// NEURONIX Time-Travel Reflink Workspace Branching Engine
// Integrates Btrfs subvolume snapshots and reflink deltas for instant project undo.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::path::{Path, PathBuf};
use std::process::Command;

pub struct BranchEngine;

impl BranchEngine {
    pub fn is_btrfs<P: AsRef<Path>>(path: P) -> bool {
        let output = Command::new("stat")
            .arg("-f")
            .arg("-c")
            .arg("%T")
            .arg(path.as_ref())
            .output();

        if let Ok(o) = output {
            let fs_type = String::from_utf8_lossy(&o.stdout).trim().to_lowercase();
            return fs_type == "btrfs";
        }
        false
    }

    pub fn create_branch<P: AsRef<Path>>(source_path: P, branch_name: &str) -> Result<PathBuf, String> {
        let source = source_path.as_ref();
        if !source.exists() {
            return Err(format!("Source path does not exist: {}", source.display()));
        }

        let base = source.file_name().and_then(|n| n.to_str()).unwrap_or("ws");
        let branch_dir = source.parent().unwrap_or_else(|| Path::new("/tmp")).join(format!(".branch_{}_{}", base, branch_name));

        if Self::is_btrfs(source) {
            let status = Command::new("btrfs")
                .arg("subvolume")
                .arg("snapshot")
                .arg(source)
                .arg(&branch_dir)
                .status();

            if let Ok(s) = status {
                if s.success() {
                    return Ok(branch_dir);
                }
            }
        }

        // Fast reflink fallback (copy-on-write without full data duplication)
        let status = Command::new("cp")
            .arg("-a")
            .arg("--reflink=auto")
            .arg(source)
            .arg(&branch_dir)
            .status();

        match status {
            Ok(s) if s.success() => Ok(branch_dir),
            _ => Err("Failed to create workspace branch with reflink/CoW".to_string()),
        }
    }

    pub fn revert_branch<P: AsRef<Path>>(source_path: P, branch_path: P) -> Result<(), String> {
        let source = source_path.as_ref();
        let branch = branch_path.as_ref();

        if !branch.exists() {
            return Err(format!("Branch path does not exist: {}", branch.display()));
        }

        // CoW reflink snapshot restore back to source
        let status = Command::new("cp")
            .arg("-a")
            .arg("--reflink=auto")
            .arg(format!("{}/.", branch.display()))
            .arg(source)
            .status();

        match status {
            Ok(s) if s.success() => Ok(()),
            _ => Err("Failed to restore workspace from snapshot branch".to_string()),
        }
    }
}
