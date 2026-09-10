// ==============================================================================
// NEURONIX Conductor Control Protocol Client (UNIX Domain Socket)
// Native client communicating with conductor-runtime over JSON-RPC 2.0.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static REQUEST_COUNTER: AtomicU64 = AtomicU64::new(1);

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

        let request_id = REQUEST_COUNTER.fetch_add(1, Ordering::SeqCst);
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

    pub fn get_surface_state(&self) -> Result<String, String> {
        self.call("surface.state", "{}")
    }

    pub fn resolve_proposal(&self, proposal_hash: &str, action: &str) -> Result<String, String> {
        let params = format!("{{\"proposal_hash\":\"{}\",\"action\":\"{}\"}}", proposal_hash, action);
        self.call("proposal.resolve", &params)
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
    use std::os::unix::net::UnixListener;
    use std::thread;

    #[test]
    fn test_default_socket_path() {
        let p = ConductorClient::default_socket_path();
        assert!(p.to_string_lossy().ends_with("conductor.sock"));
    }

    #[test]
    fn test_client_call_mock_server() {
        let temp_sock = format!("/tmp/conductor-test-mock-{}.sock", std::process::id());
        let _ = std::fs::remove_file(&temp_sock);

        let listener = UnixListener::bind(&temp_sock).expect("bind mock unix socket");

        let handle = thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                if reader.read_line(&mut line).is_ok() {
                    let resp = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"status\":\"PONG\"}}\n";
                    let _ = stream.write_all(resp.as_bytes());
                }
            }
        });

        let client = ConductorClient::new(Some(PathBuf::from(&temp_sock)));
        let is_pong = client.ping().expect("ping mock server");
        assert!(is_pong);

        let _ = handle.join();
        let _ = std::fs::remove_file(&temp_sock);
    }
}
