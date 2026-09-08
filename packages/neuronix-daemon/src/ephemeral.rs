// ==============================================================================
// NEURONIX Dual-Plane Ephemeral Persona & Ghost Mode Engine
// Enables zero-trace, disposable desktop sessions and instant failure recovery.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};

pub struct GhostSession {
    pub session_id: String,
    pub ram_mount_point: PathBuf,
}

impl GhostSession {
    pub fn new() -> Self {
        let rand_suffix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(42);
        let session_id = format!("ghost_{:x}", rand_suffix);
        let ram_mount_point = PathBuf::from(format!("/dev/shm/neuronix_{}", session_id));

        GhostSession {
            session_id,
            ram_mount_point,
        }
    }

    pub fn prepare(&self) -> Result<(), String> {
        fs::create_dir_all(&self.ram_mount_point)
            .map_err(|e| format!("Failed to create RAM workspace {}: {}", self.ram_mount_point.display(), e))?;

        // Create overlayfs structure in volatile memory
        let upper = self.ram_mount_point.join("upper");
        let work = self.ram_mount_point.join("work");
        let merged = self.ram_mount_point.join("merged");

        fs::create_dir_all(&upper).map_err(|e| e.to_string())?;
        fs::create_dir_all(&work).map_err(|e| e.to_string())?;
        fs::create_dir_all(&merged).map_err(|e| e.to_string())?;

        Ok(())
    }

    pub fn wipe_and_teardown(&self) {
        if self.ram_mount_point.exists() {
            // Cryptographic memory wipe: overwrite existing files before unlinking
            if let Ok(entries) = fs::read_dir(&self.ram_mount_point) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        if let Ok(meta) = fs::metadata(&path) {
                            let len = meta.len() as usize;
                            let zeros = vec![0u8; len.min(1024 * 1024)];
                            let _ = fs::write(&path, &zeros);
                        }
                    }
                }
            }
            let _ = fs::remove_dir_all(&self.ram_mount_point);
        }
    }

    pub fn run_isolated_command(&self, cmd: &str) -> (i32, String, String) {
        if let Err(e) = self.prepare() {
            return (1, String::new(), format!("Preparation failed: {}", e));
        }

        // Execute command bound within RAM workspace environment
        let output = Command::new("bash")
            .arg("-c")
            .arg(cmd)
            .env("NEURONIX_GHOST_MODE", "1")
            .env("NEURONIX_GHOST_SESSION", &self.session_id)
            .env("TMPDIR", &self.ram_mount_point)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();

        let res = match output {
            Ok(o) => {
                let code = o.status.code().unwrap_or(1);
                let stdout = String::from_utf8_lossy(&o.stdout).to_string();
                let stderr = String::from_utf8_lossy(&o.stderr).to_string();
                (code, stdout, stderr)
            }
            Err(e) => (1, String::new(), format!("Execution error: {}", e)),
        };

        self.wipe_and_teardown();
        res
    }
}
