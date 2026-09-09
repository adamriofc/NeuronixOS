// ==============================================================================
// NEURONIX Autonomous Micro-Rust Systems Daemon & AST Engine
// High-performance, memory-safe system substrate daemon (<3MB RAM, <3MB Binary).
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

mod ast;
mod ephemeral;
mod ebpf;
mod branch;
mod crypto;
pub mod state;
pub mod hyperion;

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::thread;

use ast::{handle_jsonrpc, SystemAst, CANONICAL_VERSION};
use ephemeral::GhostSession;
use ebpf::EbpfLsmEngine;
use branch::BranchEngine;

const DEFAULT_SOCKET_PATH: &str = "/run/neuronix/ast.sock";
const FALLBACK_SOCKET_PATH: &str = "/tmp/neuronix_ast.sock";

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 || args.contains(&"--help".to_string()) || args.contains(&"-h".to_string()) {
        print_usage();
        return;
    }

    if args.contains(&"--version".to_string()) || args.contains(&"-v".to_string()) {
        println!("neuronix-daemon {} (Apache-2.0)", CANONICAL_VERSION);
        return;
    }

    // Direct AST dump (One-shot mode)
    if args.contains(&"--ast".to_string()) {
        let ast = SystemAst::probe();
        println!("{}", ast.to_json());
        return;
    }

    // Direct JSON-RPC evaluation (One-shot mode)
    if let Some(pos) = args.iter().position(|a| a == "--eval" || a == "-e") {
        if pos + 1 < args.len() {
            let resp = handle_jsonrpc(&args[pos + 1]);
            println!("{}", resp);
            return;
        }
    }

    // Direct ping (One-shot mode)
    if args.contains(&"--ping".to_string()) {
        let resp = handle_jsonrpc(r#"{"jsonrpc":"2.0","method":"system/ping","id":1}"#);
        println!("{}", resp);
        return;
    }

    // Direct Provable State Root probe and verification (One-shot mode)
    if let Some(pos) = args.iter().position(|a| a == "--state") {
        if pos + 1 < args.len() && args[pos + 1] == "verify" {
            let res = state::StateEngine::verify_state();
            println!("{}", res);
            return;
        }
        let state = state::StateEngine::probe_state();
        println!("{}", state);
        return;
    }

    // Direct Hyperion Execution Plane broker (One-shot mode)
    if let Some(pos) = args.iter().position(|a| a == "--hyperion") {
        if pos + 1 < args.len() {
            let sub = &args[pos + 1];
            if sub == "negotiate" {
                let workload = if pos + 2 < args.len() { &args[pos + 2] } else { "workload" };
                let hds = hyperion::HyperionBroker::negotiate_domain(workload, "direct-execution", "tier1", false, 2048);
                println!("{}", hds);
                return;
            } else if sub == "proof" {
                let state_root = if pos + 2 < args.len() { &args[pos + 2] } else { "0000000000000000000000000000000000000000000000000000000000000000" };
                let hds_spec = if pos + 3 < args.len() { &args[pos + 3] } else { "DOM-ACTIVE" };
                let policy_hash = if pos + 4 < args.len() { &args[pos + 4] } else { "0000000000000000000000000000000000000000000000000000000000000000" };
                let input_hash = if pos + 5 < args.len() { &args[pos + 5] } else { "0000000000000000000000000000000000000000000000000000000000000000" };
                let output_digest = if pos + 6 < args.len() { &args[pos + 6] } else { "0000000000000000000000000000000000000000000000000000000000000000" };
                let evidence_json = if pos + 7 < args.len() { Some(args[pos + 7].as_str()) } else { None };
                let exit_code = if pos + 8 < args.len() { args[pos + 8].parse::<i32>().unwrap_or(0) } else { 0 };
                let tier = if pos + 9 < args.len() { &args[pos + 9] } else { "TIER_1_RAM_GHOST" };

                let proof = hyperion::HyperionBroker::generate_proof(
                    state_root,
                    hds_spec,
                    policy_hash,
                    input_hash,
                    output_digest,
                    evidence_json,
                    exit_code,
                    tier
                );
                println!("{}", proof);
                return;
            } else if sub == "verify" {
                let proof_json = if pos + 2 < args.len() { &args[pos + 2] } else { "{}" };
                let spec_json = if pos + 3 < args.len() { Some(args[pos + 3].as_str()) } else { None };
                let (valid, msg) = hyperion::HyperionBroker::verify_domain_proof(proof_json, spec_json);
                println!(r#"{{"valid":{},"message":"{}"}}"#, valid, msg);
                return;
            }
        }
        let caps = hyperion::HyperionBroker::probe_capabilities();
        println!("{}", caps);
        return;
    }

    // Direct control-plane status check (One-shot mode)
    if args.contains(&"--status".to_string()) {
        let resp = handle_jsonrpc(r#"{"jsonrpc":"2.0","method":"system/status","id":1}"#);
        println!("{}", resp);
        return;
    }

    // Direct facts probe (One-shot mode)
    if args.contains(&"--facts".to_string()) {
        let resp = handle_jsonrpc(r#"{"jsonrpc":"2.0","method":"system/facts","id":1}"#);
        println!("{}", resp);
        return;
    }

    // Direct topology probe (One-shot mode)
    if args.contains(&"--topology".to_string()) {
        let resp = handle_jsonrpc(r#"{"jsonrpc":"2.0","method":"system/topology","id":1}"#);
        println!("{}", resp);
        return;
    }

    // Ghost execution
    if let Some(pos) = args.iter().position(|a| a == "--ghost-run") {
        if pos + 1 < args.len() {
            let cmd = &args[pos + 1];
            let ghost = GhostSession::new();
            let (code, stdout, stderr) = ghost.run_isolated_command(cmd);
            if !stdout.is_empty() {
                print!("{}", stdout);
            }
            if !stderr.is_empty() {
                eprint!("{}", stderr);
            }
            println!("Ghost RAM Session vaporized. Zero bytes retained on disk.");
            std::process::exit(code);
        } else {
            eprintln!("Error: --ghost-run requires a command string");
            std::process::exit(1);
        }
    }

    // eBPF LSM Policy Contract
    if let Some(pos) = args.iter().position(|a| a == "--policy") {
        if pos + 1 < args.len() {
            let pkg = &args[pos + 1];
            let engine = EbpfLsmEngine::probe();
            println!("{}", engine.generate_policy_contract(pkg, &["/nix/store", "/tmp"]));
            return;
        }
    }

    // Workspace branch create
    if let Some(pos) = args.iter().position(|a| a == "--branch-create") {
        if pos + 2 < args.len() {
            let src = &args[pos + 1];
            let name = &args[pos + 2];
            match BranchEngine::create_branch(src, name) {
                Ok(path) => {
                    println!(r#"{{"status":"SUCCESS","branch_path":"{}"}}"#, path.display());
                    return;
                }
                Err(e) => {
                    eprintln!(r#"{{"status":"ERROR","error":"{}"}}"#, e);
                    std::process::exit(1);
                }
            }
        }
    }

    // Workspace branch revert
    if let Some(pos) = args.iter().position(|a| a == "--branch-revert") {
        if pos + 2 < args.len() {
            let src = &args[pos + 1];
            let branch = &args[pos + 2];
            match BranchEngine::revert_branch(src, branch) {
                Ok(()) => {
                    println!(r#"{{"status":"SUCCESS","message":"Reverted to branch"}}"#);
                    return;
                }
                Err(e) => {
                    eprintln!(r#"{{"status":"ERROR","error":"{}"}}"#, e);
                    std::process::exit(1);
                }
            }
        }
    }

    // Daemon mode
    if args.contains(&"--daemon".to_string()) {
        let socket_path = get_socket_path(&args);
        run_daemon(socket_path);
        return;
    }

    eprintln!("Unknown argument: {}", args[1]);
    print_usage();
    std::process::exit(1);
}

fn print_usage() {
    println!("NEURONIX Autonomous Systems Daemon (v{})", CANONICAL_VERSION);
    println!("Usage: neuronix-daemon [OPTIONS]");
    println!();
    println!("Options:");
    println!("  --daemon                  Run async UNIX domain socket listener");
    println!("  --socket <path>           Specify custom UNIX domain socket path");
    println!("  --ast                     Emit JSON-formatted System State AST and exit");
    println!("  --state                   Emit JSON-formatted Provable State Root and exit");
    println!("  --facts                   Emit JSON-formatted hardware facts and exit");
    println!("  --topology                Emit JSON-formatted system topology summary and exit");
    println!("  --hyperion                Emit Hyperion execution plane capabilities and exit");
    println!("  --ping                    Verify AST engine responsiveness and exit");
    println!("  --ghost-run <cmd>         Execute command in ephemeral RAM overlay");
    println!("  --policy <pkg>            Generate declarative eBPF LSM policy contract");
    println!("  --branch-create <s> <n>   Create Btrfs/Reflink workspace branch");
    println!("  --branch-revert <s> <b>   Restore workspace from snapshot branch (CoW reflink)");
    println!("  --version, -v             Print version and exit");
    println!("  --help, -h                Print this help message");
}

fn get_socket_path(args: &[String]) -> PathBuf {
    if let Some(pos) = args.iter().position(|a| a == "--socket") {
        if pos + 1 < args.len() {
            return PathBuf::from(&args[pos + 1]);
        }
    }

    // Attempt default /run/neuronix/ast.sock, fallback to /tmp/neuronix_ast.sock
    let default_path = Path::new(DEFAULT_SOCKET_PATH);
    if let Some(parent) = default_path.parent() {
        if fs::create_dir_all(parent).is_ok() {
            return default_path.to_path_buf();
        }
    }

    PathBuf::from(FALLBACK_SOCKET_PATH)
}

fn run_daemon(socket_path: PathBuf) {
    println!("[NEURONIX-DAEMON] Initializing systems daemon v{}", CANONICAL_VERSION);

    // Unlink old socket if present
    if socket_path.exists() {
        let _ = fs::remove_file(&socket_path);
    }

    if let Some(parent) = socket_path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let listener = match UnixListener::bind(&socket_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[NEURONIX-DAEMON] Failed to bind socket at {}: {}", socket_path.display(), e);
            std::process::exit(1);
        }
    };

    // Set permission 0660
    let _ = fs::set_permissions(&socket_path, fs::Permissions::from_mode(0o660));

    println!("[NEURONIX-DAEMON] Listening on UNIX domain socket: {}", socket_path.display());

    // Register genuine POSIX signal handler for graceful shutdown and socket unlinking
    register_signals(&socket_path);

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                thread::spawn(|| {
                    handle_client(stream);
                });
            }
            Err(e) => {
                eprintln!("[NEURONIX-DAEMON] Connection error: {}", e);
            }
        }
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PeerCred {
    pub pid: i32,
    pub uid: u32,
    pub gid: u32,
}

pub fn get_peer_credentials(stream: &UnixStream) -> Option<PeerCred> {
    let fd = stream.as_raw_fd();
    let mut cred = PeerCred { pid: 0, uid: 0, gid: 0 };
    let mut len = std::mem::size_of::<PeerCred>() as u32;
    unsafe {
        let ret = getsockopt(
            fd,
            1,  // SOL_SOCKET
            17, // SO_PEERCRED (Linux)
            std::ptr::addr_of_mut!(cred) as *mut std::ffi::c_void,
            std::ptr::addr_of_mut!(len),
        );
        if ret == 0 {
            Some(cred)
        } else {
            None
        }
    }
}

fn handle_client(mut stream: UnixStream) {
    let _peer_cred = get_peer_credentials(&stream);
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut line = String::new();

    while let Ok(bytes) = reader.read_line(&mut line) {
        if bytes == 0 {
            break;
        }
        let response = handle_jsonrpc(&line);
        let _ = stream.write_all(response.as_bytes());
        let _ = stream.write_all(b"\n");
        let _ = stream.flush();
        line.clear();
    }
}

static mut GLOBAL_SOCKET_PATH: [u8; 4096] = [0; 4096];
static mut GLOBAL_SOCKET_LEN: usize = 0;

extern "C" {
    fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
    fn unlink(pathname: *const u8) -> i32;
    fn write(fd: i32, buf: *const u8, count: usize) -> isize;
    fn getsockopt(
        sockfd: i32,
        level: i32,
        optname: i32,
        optval: *mut std::ffi::c_void,
        optlen: *mut u32,
    ) -> i32;
}

extern "C" fn sig_handler(_sig: i32) {
    unsafe {
        if GLOBAL_SOCKET_LEN > 0 {
            unlink(std::ptr::addr_of!(GLOBAL_SOCKET_PATH) as *const u8);
        }
        let msg = b"\n[NEURONIX-DAEMON] Shutdown signal received. Socket unlinked gracefully.\n";
        let _ = write(2, msg.as_ptr(), msg.len());
        std::process::exit(0);
    }
}

fn register_signals(socket_path: &Path) {
    let path_str = socket_path.to_string_lossy();
    let bytes = path_str.as_bytes();
    if bytes.len() < 4095 {
        unsafe {
            let dest = std::ptr::addr_of_mut!(GLOBAL_SOCKET_PATH) as *mut u8;
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), dest, bytes.len());
            *dest.add(bytes.len()) = 0;
            GLOBAL_SOCKET_LEN = bytes.len();
            signal(2, sig_handler);  // SIGINT
            signal(15, sig_handler); // SIGTERM
        }
    }
}

