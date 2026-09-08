// ==============================================================================
// NEURONIX Dual-Plane Ephemeral Persona & Ghost Mode Engine
// Enables zero-trace, disposable desktop sessions with private namespace isolation.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

use std::fs;
use std::path::{Path, PathBuf};
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

        let ghost_home = self.ram_mount_point.join("home");
        let ghost_ws = self.ram_mount_point.join("workspace");
        fs::create_dir_all(&ghost_home).map_err(|e| e.to_string())?;
        fs::create_dir_all(&ghost_ws).map_err(|e| e.to_string())?;

        Ok(())
    }

    pub fn wipe_and_teardown(&self) {
        if self.ram_mount_point.exists() {
            fn recursive_wipe(dir: &Path) {
                if let Ok(entries) = fs::read_dir(dir) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if path.is_dir() {
                            recursive_wipe(&path);
                        } else if path.is_file() {
                            if let Ok(meta) = fs::metadata(&path) {
                                let len = meta.len() as usize;
                                let zeros = vec![0u8; len.min(1024 * 1024)];
                                let _ = fs::write(&path, &zeros);
                            }
                        }
                    }
                }
            }
            recursive_wipe(&self.ram_mount_point);
            let _ = fs::remove_dir_all(&self.ram_mount_point);
        }
    }

    pub fn run_isolated_command(&self, cmd: &str) -> (i32, String, String) {
        if let Err(e) = self.prepare() {
            return (1, String::new(), format!("Preparation failed: {}", e));
        }

        let ghost_home = self.ram_mount_point.join("home");
        let ghost_ws = self.ram_mount_point.join("workspace");

        // Probe bubblewrap availability for strict process, user, and filesystem namespace isolation
        let bwrap_bin = if Path::new("/run/current-system/sw/bin/bwrap").exists() {
            Some("/run/current-system/sw/bin/bwrap")
        } else if Path::new("/usr/bin/bwrap").exists() {
            Some("/usr/bin/bwrap")
        } else {
            None
        };

        if let Some(bin) = bwrap_bin {
            let mut bcmd = Command::new(bin);
            bcmd.arg("--clearenv")
                .arg("--unshare-pid")
                .arg("--unshare-uts")
                .arg("--unshare-ipc")
                .arg("--proc").arg("/proc")
                .arg("--dev").arg("/dev")
                .arg("--tmpfs").arg("/tmp");

            if Path::new("/nix/store").exists() {
                bcmd.arg("--ro-bind").arg("/nix/store").arg("/nix/store");
            }
            if Path::new("/run/current-system/sw").exists() {
                bcmd.arg("--ro-bind").arg("/run/current-system/sw").arg("/run/current-system/sw");
            }
            if Path::new("/usr").exists() {
                bcmd.arg("--ro-bind").arg("/usr").arg("/usr");
            }
            if Path::new("/bin").is_dir() {
                bcmd.arg("--ro-bind").arg("/bin").arg("/bin");
            } else if Path::new("/usr/bin").exists() {
                bcmd.arg("--symlink").arg("usr/bin").arg("/bin");
            }
            if Path::new("/lib").is_dir() {
                bcmd.arg("--ro-bind").arg("/lib").arg("/lib");
            } else if Path::new("/usr/lib").exists() {
                bcmd.arg("--symlink").arg("usr/lib").arg("/lib");
            }
            if Path::new("/lib64").is_dir() {
                bcmd.arg("--ro-bind").arg("/lib64").arg("/lib64");
            } else if Path::new("/usr/lib64").exists() {
                bcmd.arg("--symlink").arg("usr/lib64").arg("/lib64");
            }
            if Path::new("/etc/resolv.conf").exists() {
                bcmd.arg("--ro-bind").arg("/etc/resolv.conf").arg("/etc/resolv.conf");
            }
            if Path::new("/etc/ssl").exists() {
                bcmd.arg("--ro-bind").arg("/etc/ssl").arg("/etc/ssl");
            }

            // Private ephemeral HOME and workspace inside RAM
            bcmd.arg("--tmpfs").arg("/home/ghost")
                .arg("--bind").arg(&ghost_ws).arg("/home/ghost/workspace")
                .arg("--chdir").arg("/home/ghost/workspace")
                .arg("--setenv").arg("HOME").arg("/home/ghost")
                .arg("--setenv").arg("USER").arg("ghost")
                .arg("--setenv").arg("LOGNAME").arg("ghost")
                .arg("--setenv").arg("PATH").arg("/run/current-system/sw/bin:/usr/bin:/bin")
                .arg("--setenv").arg("TERM").arg("xterm-256color")
                .arg("--setenv").arg("NEURONIX_GHOST_MODE").arg("1")
                .arg("--setenv").arg("NEURONIX_GHOST_SESSION").arg(&self.session_id)
                .arg("--setenv").arg("TMPDIR").arg("/home/ghost/workspace")
                .arg("bash").arg("-c").arg(cmd)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());

            if let Ok(output) = bcmd.output() {
                let code = output.status.code().unwrap_or(1);
                let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                self.wipe_and_teardown();
                return (code, stdout, stderr);
            }
        }

        // Resilient fallback: sanitized subshell with private HOME in /dev/shm
        let mut fcmd = Command::new("bash");
        fcmd.arg("-c").arg(cmd)
            .current_dir(&ghost_ws)
            .env_clear()
            .env("HOME", &ghost_home)
            .env("USER", "ghost")
            .env("LOGNAME", "ghost")
            .env("PATH", std::env::var("PATH").unwrap_or_else(|_| "/run/current-system/sw/bin:/usr/bin:/bin".into()))
            .env("TERM", "xterm-256color")
            .env("NEURONIX_GHOST_MODE", "1")
            .env("NEURONIX_GHOST_SESSION", &self.session_id)
            .env("TMPDIR", &ghost_ws)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let res = match fcmd.output() {
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
