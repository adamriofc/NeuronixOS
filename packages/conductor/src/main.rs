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
use std::path::PathBuf;
use surface::{ProposalCard, SurfaceLayout};
use client::ConductorClient;

pub const CONDUCTOR_VERSION: &str = "1.0.4";

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
    println!("  --socket <PATH>      Connect to custom Conductor Control Socket");
    println!("  --test-render        Execute one-shot terminal frame rendering test");
    println!("  --status             Query live status via Conductor Control Socket");
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
        match client.ping() {
            Ok(true) => println!("[OK] Conductor Runtime is online and responsive."),
            Ok(false) => println!("[WARN] Conductor Runtime responded with invalid status."),
            Err(e) => eprintln!("[ERROR] Could not connect to Conductor Runtime: {}", e),
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

        let frame = layout.render_frame();
        for line in frame {
            println!("{}", line);
        }
        return;
    }

    // Default startup banner
    println!("CONDUCTOR Native Surface Engine {}", CONDUCTOR_VERSION);
    println!("Active socket: {}", ConductorClient::default_socket_path().display());
    println!("For interactive GUI/TUI mode, use within a supported graphical desktop or terminal.");
}
