// ==============================================================================
// NEURONIX Conductor Control Protocol Client (UNIX Domain Socket)
// Native client communicating with conductor-runtime over JSON-RPC 2.0.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

pub struct ConductorClient {
    socket_path: PathBuf,
}

impl ConductorClient {
    pub fn new(socket_path: Option<PathBuf>) -> Self {
        let path = socket_path.unwrap_or_else(Self::default_socket_path);
        ConductorClient { socket_path: path }
    }

    pub fn default_socket_path() -> PathBuf {
        if let Ok(env_path) = std::env::var("CONDUCTOR_SOCKET_PATH") {
            return PathBuf::from(env_path);
        }
        if let Ok(xdg) = std::env::var("XDG_RUNTIME_DIR") {
            return PathBuf::from(xdg).join("conductor.sock");
        }
        let uid = unsafe { libc_getuid() };
        let run_user = PathBuf::from(format!("/run/user/{}", uid));
        if run_user.exists() {
            return run_user.join("conductor.sock");
        }
        PathBuf::from(format!("/tmp/conductor-{}.sock", uid))
    }

    pub fn call(&self, method: &str, params_json: &str) -> Result<String, String> {
        let mut stream = UnixStream::connect(&self.socket_path)
            .map_err(|e| format!("Failed to connect to Conductor socket at {}: {}", self.socket_path.display(), e))?;

        let request_id = 1;
        let frame = format!(
            "{{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"{}\",\"params\":{}}}\n",
            request_id, method, params_json
        );

        stream.write_all(frame.as_bytes())
            .map_err(|e| format!("Failed to write to socket: {}", e))?;
        stream.flush()
            .map_err(|e| format!("Failed to flush socket: {}", e))?;

        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line)
            .map_err(|e| format!("Failed to read response from socket: {}", e))?;

        Ok(line)
    }

    pub fn ping(&self) -> Result<bool, String> {
        let resp = self.call("conductor.ping", "{}")?;
        Ok(resp.contains("\"PONG\""))
    }
}

unsafe fn libc_getuid() -> u32 {
    extern "C" {
        fn getuid() -> u32;
    }
    getuid()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_socket_path() {
        let p = ConductorClient::default_socket_path();
        assert!(p.to_string_lossy().ends_with("conductor.sock"));
    }
}
