// ==============================================================================
// NEURONIX Conductor: Native Minimalist Operating Surface & Local Agent Substrate
// One Window. 95% Canvas. Zero Bloat. Terminal-First.
// Copyright (c) 2026 NEURONIX Contributors
// Licensed under the Apache License, Version 2.0
// ==============================================================================

pub mod vt;
pub mod pty;
pub mod surface;
pub mod client;

use std::env;
use std::io::Write;
use std::path::PathBuf;
use surface::{ProposalCard, SurfaceLayout, WorkspaceTab};
use client::ConductorClient;
use pty::PtySession;

pub const CONDUCTOR_VERSION: &str = "1.0.4";

const TIOCGWINSZ: u64 = 0x5413;
const POLLIN: i16 = 0x0001;

#[repr(C)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn isatty(fd: i32) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
    fn read(fd: i32, buf: *mut u8, count: usize) -> isize;
}

fn get_terminal_size() -> (usize, usize) {
    let mut ws = Winsize {
        ws_row: 24,
        ws_col: 80,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    unsafe {
        if ioctl(1, TIOCGWINSZ, &mut ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
            return (ws.ws_col as usize, ws.ws_row as usize);
        }
    }
    (80, 24)
}

struct RawModeGuard {
    active: bool,
}

impl RawModeGuard {
    fn enter() -> Self {
        let status = std::process::Command::new("stty")
            .arg("raw")
            .arg("-echo")
            .status();
        let active = status.map(|s| s.success()).unwrap_or(false);
        if active {
            print!("\x1b[?25l"); // Hide cursor during custom frame updates
            let _ = std::io::stdout().flush();
        }
        RawModeGuard { active }
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        if self.active {
            let _ = std::process::Command::new("stty").arg("sane").status();
            print!("\x1b[?25h\x1b[0m\n"); // Show cursor, reset attributes
            let _ = std::io::stdout().flush();
        }
    }
}

fn print_usage() {
    println!("CONDUCTOR - Native Minimalist Operating Surface & Terminal Subsystem");
    println!("Version: {}", CONDUCTOR_VERSION);
    println!();
    println!("Usage:");
    println!("  conductor [OPTIONS]");
    println!();
    println!("Options:");
    println!("  -h, --help           Show this help manual");
    println!("  -v, --version        Show version information");
    println!("  -i, --interactive    Launch interactive full-screen native terminal surface");
    println!("  --socket <PATH>      Connect to custom Conductor Control Socket");
    println!("  --test-render        Execute one-shot terminal frame rendering test");
    println!("  --status             Query live status via Conductor Control Socket");
    println!();
    println!("Interactive Keybindings:");
    println!("  Ctrl-A 1             Switch to Workspace Tab 1 (Terminal Canvas)");
    println!("  Ctrl-A 2             Switch to Workspace Tab 2 (Vital Observation)");
    println!("  Ctrl-A 3             Switch to Workspace Tab 3 (Proposals Deck)");
    println!("  Ctrl-A 4             Switch to Workspace Tab 4 (Capabilities Catalog)");
    println!("  Ctrl-A q             Exit Conductor Surface");
    println!("  [y] / [n]            Approve or reject active mutation proposal");
    println!("  [Esc]                Dismiss active proposal overlay");
}

fn render_screen(layout: &SurfaceLayout) {
    let frame = layout.render_frame();
    let mut out = String::with_capacity(layout.width * layout.height + 64);
    out.push_str("\x1b[H"); // Cursor to home (1,1)
    for (i, line) in frame.iter().enumerate() {
        out.push_str(line);
        if i + 1 < frame.len() {
            out.push_str("\r\n");
        }
    }
    print!("{}", out);
    let _ = std::io::stdout().flush();
}

fn run_interactive_surface(socket_arg: Option<PathBuf>) -> Result<(), String> {
    let is_stdin_tty = unsafe { isatty(0) == 1 };
    let is_stdout_tty = unsafe { isatty(1) == 1 };

    if !is_stdin_tty || !is_stdout_tty {
        return Err("Interactive mode requires a standard POSIX TTY terminal environment.".to_string());
    }

    let (cols, rows) = get_terminal_size();
    let client = ConductorClient::new(socket_arg);
    let mut layout = SurfaceLayout::new(cols, rows);

    // Initial query to Conductor Runtime if socket is available
    if let Ok(state) = client.get_surface_state() {
        layout.vital_health_status = if state.lifecycle_state == "ACTIVE" {
            "NOMINAL".to_string()
        } else {
            state.lifecycle_state
        };
        if state.pending_proposals > 0 {
            layout.show_proposal(ProposalCard {
                title: "Pending Mutation Gate".to_string(),
                skill_id: "system.mutation".to_string(),
                severity: "NOTICE".to_string(),
                proposal_hash: "0000000000000000".to_string(),
                explanation: format!("{} pending proposal(s) require review", state.pending_proposals),
            });
        }
    }

    let pty_rows = (rows.saturating_sub(1)).max(1) as u16;
    let mut pty = PtySession::open(cols as u16, pty_rows)
        .map_err(|e| format!("PTY allocation failed: {}", e))?;

    let shell_prog = env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
    let mut child = pty.spawn_process(&shell_prog, &[])
        .map_err(|e| format!("Failed to spawn shell '{}': {}", shell_prog, e))?;

    let _raw_guard = RawModeGuard::enter();
    render_screen(&layout);

    let mut in_prefix = false;
    let mut stdin_buf = [0u8; 1024];
    let mut pty_buf = [0u8; 4096];

    loop {
        // Check if child exited
        if let Ok(Some(status)) = child.try_wait() {
            let _ = status;
            break;
        }

        let mut fds = [
            PollFd {
                fd: 0,
                events: POLLIN,
                revents: 0,
            },
            PollFd {
                fd: pty.master_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
        ];

        let poll_res = unsafe { poll(fds.as_mut_ptr(), 2, 80) };
        if poll_res < 0 {
            break;
        }

        let mut needs_render = false;

        // Process stdin input
        if fds[0].revents & POLLIN != 0 {
            let n = unsafe { read(0, stdin_buf.as_mut_ptr(), stdin_buf.len()) };
            if n <= 0 {
                break;
            }
            let bytes = &stdin_buf[..n as usize];

            for &b in bytes {
                if in_prefix {
                    in_prefix = false;
                    match b {
                        b'1' => {
                            layout.set_tab(WorkspaceTab::Terminal);
                            needs_render = true;
                        }
                        b'2' => {
                            layout.set_tab(WorkspaceTab::Vital);
                            needs_render = true;
                        }
                        b'3' => {
                            layout.set_tab(WorkspaceTab::Proposals);
                            needs_render = true;
                        }
                        b'4' => {
                            layout.set_tab(WorkspaceTab::Capabilities);
                            needs_render = true;
                        }
                        b'q' | 3 => {
                            // Ctrl-A q or Ctrl-A Ctrl-C exits Conductor
                            return Ok(());
                        }
                        1 => {
                            // Escaped Ctrl-A, send literal byte to PTY
                            let _ = pty.write_all(&[1]);
                        }
                        _ => {}
                    }
                    continue;
                }

                if b == 1 {
                    // Ctrl-A prefix
                    in_prefix = true;
                    continue;
                }

                // Handle Proposal Overlay Responses when overlay is active
                if layout.active_overlay.is_some() {
                    if let Some(surface::OverlayType::SkillProposal(ref prop)) = layout.active_overlay.clone() {
                        if b == b'y' || b == b'Y' {
                            let _ = client.resolve_proposal(&prop.proposal_hash, "APPROVE");
                            layout.dismiss_overlay();
                            layout.set_toast("Proposal approved and executed".to_string());
                            needs_render = true;
                            continue;
                        } else if b == b'n' || b == b'N' {
                            let _ = client.resolve_proposal(&prop.proposal_hash, "REJECT");
                            layout.dismiss_overlay();
                            layout.set_toast("Proposal rejected".to_string());
                            needs_render = true;
                            continue;
                        } else if b == 0x1b {
                            // Esc dismisses overlay
                            layout.dismiss_overlay();
                            needs_render = true;
                            continue;
                        }
                    }
                }

                // Normal workspace interaction
                match layout.active_tab {
                    WorkspaceTab::Terminal => {
                        let _ = pty.write_all(&[b]);
                    }
                    WorkspaceTab::Vital | WorkspaceTab::Proposals | WorkspaceTab::Capabilities => {
                        if b == b'1' {
                            layout.set_tab(WorkspaceTab::Terminal);
                            needs_render = true;
                        } else if b == b'2' {
                            layout.set_tab(WorkspaceTab::Vital);
                            needs_render = true;
                        } else if b == b'3' {
                            layout.set_tab(WorkspaceTab::Proposals);
                            needs_render = true;
                        } else if b == b'4' {
                            layout.set_tab(WorkspaceTab::Capabilities);
                            needs_render = true;
                        } else if b == 0x1b || b == b'q' {
                            layout.set_tab(WorkspaceTab::Terminal);
                            needs_render = true;
                        }
                    }
                }
            }
        }

        // Process PTY output
        if fds[1].revents & POLLIN != 0 {
            let n = unsafe { read(pty.master_raw_fd(), pty_buf.as_mut_ptr(), pty_buf.len()) };
            if n > 0 {
                layout.terminal.write_bytes(&pty_buf[..n as usize]);
                if layout.active_tab == WorkspaceTab::Terminal {
                    needs_render = true;
                }
            }
        }

        if needs_render {
            render_screen(&layout);
        }
    }

    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.contains(&"-h".to_string()) || args.contains(&"--help".to_string()) {
        print_usage();
        return;
    }

    if args.contains(&"-v".to_string()) || args.contains(&"--version".to_string()) {
        println!("conductor {} (Apache-2.0)", CONDUCTOR_VERSION);
        return;
    }

    let socket_arg = args.windows(2).find(|w| w[0] == "--socket").map(|w| PathBuf::from(&w[1]));

    if args.contains(&"--status".to_string()) {
        let client = ConductorClient::new(socket_arg);
        println!("NEURONIX Conductor Surface Status (v{})", CONDUCTOR_VERSION);
        println!("Socket Target: {}", ConductorClient::default_socket_path().display());
        match client.ping() {
            Ok(true) => {
                println!("[OK] Conductor Runtime is online and responsive.");
                if let Ok(state) = client.get_surface_state() {
                    println!("  - Lifecycle State:    {}", state.lifecycle_state);
                    println!("  - GUI Attached:       {}", state.gui_attached);
                    println!("  - Active Connections: {}", state.active_connections);
                    println!("  - Pending Proposals:  {}", state.pending_proposals);
                    println!("  - Topbar Banner:      {}", state.topbar);
                }
            }
            Ok(false) => println!("[WARN] Conductor Runtime responded with non-PONG status."),
            Err(e) => eprintln!("[OFFLINE] Conductor Runtime not reachable: {}", e),
        }
        return;
    }

    if args.contains(&"--test-render".to_string()) {
        let mut layout = SurfaceLayout::new(80, 24);
        layout.terminal.write_str("NEURONIX Conductor v1.0.4 Terminal Canvas\nZero-Idle Runtime Broker Connected.\nType 'neuronix doctor' or run skills directly.");
        layout.show_proposal(ProposalCard {
            title: "Storage Layout Plan".to_string(),
            skill_id: "storage.plan".to_string(),
            severity: "NOTICE".to_string(),
            proposal_hash: "9876543210fedcba".to_string(),
            explanation: "Evaluate btrfs subvolumes".to_string(),
        });

        println!("--- FRAME 1: TERMINAL CANVAS WITH SLIDE-OVER PROPOSAL ---");
        for line in layout.render_frame() {
            println!("{}", line);
        }

        println!("\n--- FRAME 2: VITAL LABORATORY VIEW ---");
        layout.set_tab(WorkspaceTab::Vital);
        for line in layout.render_frame() {
            println!("{}", line);
        }

        println!("\n--- FRAME 3: PROPOSALS DECK VIEW ---");
        layout.set_tab(WorkspaceTab::Proposals);
        for line in layout.render_frame() {
            println!("{}", line);
        }

        println!("\n--- FRAME 4: CAPABILITIES CATALOG VIEW ---");
        layout.set_tab(WorkspaceTab::Capabilities);
        for line in layout.render_frame() {
            println!("{}", line);
        }
        return;
    }

    let is_interactive = args.contains(&"-i".to_string()) || args.contains(&"--interactive".to_string());
    let is_stdout_tty = unsafe { isatty(1) == 1 };

    if is_interactive || (args.len() == 1 && is_stdout_tty) {
        if let Err(e) = run_interactive_surface(socket_arg) {
            eprintln!("[ERROR] Failed to start interactive Conductor surface: {}", e);
            std::process::exit(1);
        }
        return;
    }

    // Default non-interactive banner
    println!("CONDUCTOR Native Surface Engine {}", CONDUCTOR_VERSION);
    println!("Active socket: {}", ConductorClient::default_socket_path().display());
    println!("For interactive terminal surface, run with '--interactive' in a TTY terminal.");
    println!("Run 'conductor --help' for options and keybindings.");
}
