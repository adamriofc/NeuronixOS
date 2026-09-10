// ==============================================================================
// NEURONIX Conductor Terminal Subsystem: POSIX Pseudo-Terminal (PTY) Abstraction
// Provides zero-dependency, safe PTY allocation, process spawning, and window resizing.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

use std::ffi::CStr;
use std::fs::File;
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::{FromRawFd, RawFd};
use std::process::{Command, Stdio};

const O_RDWR: i32 = 0o2;
const O_NOCTTY: i32 = 0o400;
const TIOCSWINSZ: u64 = 0x5414;

#[repr(C)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

extern "C" {
    fn posix_openpt(flags: i32) -> i32;
    fn grantpt(fd: i32) -> i32;
    fn unlockpt(fd: i32) -> i32;
    fn ptsname(fd: i32) -> *const i8;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn close(fd: i32) -> i32;
}

pub struct PtySession {
    master_fd: RawFd,
    slave_name: String,
    master_file: Option<File>,
}

impl PtySession {
    pub fn open(cols: u16, rows: u16) -> Result<Self, String> {
        unsafe {
            let master_fd = posix_openpt(O_RDWR | O_NOCTTY);
            if master_fd < 0 {
                return Err("Failed to open pseudoterminal master with posix_openpt".to_string());
            }

            if grantpt(master_fd) != 0 {
                close(master_fd);
                return Err("Failed to grantpt on pseudoterminal".to_string());
            }

            if unlockpt(master_fd) != 0 {
                close(master_fd);
                return Err("Failed to unlockpt on pseudoterminal".to_string());
            }

            let pts_ptr = ptsname(master_fd);
            if pts_ptr.is_null() {
                close(master_fd);
                return Err("Failed to resolve pseudoterminal slave name via ptsname".to_string());
            }

            let slave_name = CStr::from_ptr(pts_ptr).to_string_lossy().into_owned();

            // Set initial window size
            let ws = Winsize {
                ws_row: rows,
                ws_col: cols,
                ws_xpixel: 0,
                ws_ypixel: 0,
            };
            ioctl(master_fd, TIOCSWINSZ, &ws);

            let master_file = File::from_raw_fd(master_fd);

            Ok(PtySession {
                master_fd,
                slave_name,
                master_file: Some(master_file),
            })
        }
    }

    pub fn slave_name(&self) -> &str {
        &self.slave_name
    }

    pub fn resize(&self, cols: u16, rows: u16) -> Result<(), String> {
        let ws = Winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        unsafe {
            if ioctl(self.master_fd, TIOCSWINSZ, &ws) != 0 {
                return Err("Failed to resize PTY window via ioctl(TIOCSWINSZ)".to_string());
            }
        }
        Ok(())
    }

    pub fn spawn_process(&self, program: &str, args: &[&str]) -> Result<std::process::Child, String> {
        let slave_file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(O_NOCTTY)
            .open(&self.slave_name)
            .map_err(|e| format!("Failed to open slave PTY {}: {}", self.slave_name, e))?;

        let slave_out = slave_file.try_clone().map_err(|e| e.to_string())?;
        let slave_err = slave_file.try_clone().map_err(|e| e.to_string())?;

        let child = Command::new(program)
            .args(args)
            .stdin(Stdio::from(slave_file))
            .stdout(Stdio::from(slave_out))
            .stderr(Stdio::from(slave_err))
            .spawn()
            .map_err(|e| format!("Failed to spawn process in PTY: {}", e))?;

        Ok(child)
    }

    pub fn write_all(&mut self, data: &[u8]) -> std::io::Result<()> {
        if let Some(ref mut file) = self.master_file {
            file.write_all(data)?;
            file.flush()
        } else {
            Err(std::io::Error::new(std::io::ErrorKind::NotConnected, "PTY file closed"))
        }
    }

    pub fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if let Some(ref mut file) = self.master_file {
            file.read(buf)
        } else {
            Err(std::io::Error::new(std::io::ErrorKind::NotConnected, "PTY file closed"))
        }
    }
}

impl Drop for PtySession {
    fn drop(&mut self) {
        // master_file manages fd cleanup when dropped
        self.master_file.take();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pty_allocation_and_resize() {
        let pty = PtySession::open(80, 24).expect("PTY open must succeed on Linux host");
        assert!(pty.slave_name().starts_with("/dev/pts/"));
        pty.resize(120, 40).expect("PTY resize must succeed");
    }
}
