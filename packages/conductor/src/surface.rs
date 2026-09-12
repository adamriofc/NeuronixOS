// ==============================================================================
// NEURONIX Conductor Surface & Workspace Canvas Engine
// Renders the 95% minimalist terminal canvas, subtle topbar, and ephemeral proposal cards.
// Adheres strictly to SPEC-NRX-CND-018 and SPEC-NRX-CND-021.
// ==============================================================================

use crate::vt::TerminalBuffer;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceTab {
    Terminal,
    Vital,
    Proposals,
    Capabilities,
}

pub struct SurfaceLayout {
    pub width: usize,
    pub height: usize,
    pub active_tab: WorkspaceTab,
    pub terminal: TerminalBuffer,
    pub active_overlay: Option<OverlayType>,
    pub vital_health_status: String,
    pub active_generation: u32,
    pub vital_data: Option<VitalGlanceData>,
    pub pending_proposals: Vec<ProposalCard>,
    pub toast_message: Option<String>,
}

#[derive(Debug, Clone)]
pub enum OverlayType {
    SkillProposal(ProposalCard),
    VitalGlance(VitalGlanceData),
}

#[derive(Debug, Clone)]
pub struct ProposalCard {
    pub title: String,
    pub skill_id: String,
    pub severity: String,
    pub proposal_hash: String,
    pub explanation: String,
}

#[derive(Debug, Clone)]
pub struct VitalGlanceData {
    pub cpu_load: Option<String>,
    pub memory_info: Option<String>,
    pub cpu_temp_celsius: Option<f32>,
    pub nixos_generation: Option<u32>,
    pub state_root_digest: Option<String>,
    pub daemon_status: Option<String>,
    pub virtualization: Option<String>,
}

impl SurfaceLayout {
    pub fn new(width: usize, height: usize) -> Self {
        let width = width.max(40);
        let height = height.max(10);
        let term_rows = height.saturating_sub(1);
        SurfaceLayout {
            width,
            height,
            active_tab: WorkspaceTab::Terminal,
            terminal: TerminalBuffer::new(width, term_rows),
            active_overlay: None,
            vital_health_status: "NOMINAL".to_string(),
            active_generation: 1,
            vital_data: None,
            pending_proposals: Vec::new(),
            toast_message: None,
        }
    }

    pub fn resize(&mut self, width: usize, height: usize) {
        let width = width.max(40);
        let height = height.max(10);
        let term_rows = height.saturating_sub(1);
        self.width = width;
        self.height = height;
        self.terminal.resize(width, term_rows);
    }

    pub fn set_tab(&mut self, tab: WorkspaceTab) {
        self.active_tab = tab;
    }

    pub fn set_toast(&mut self, msg: String) {
        self.toast_message = Some(msg);
    }

    pub fn clear_toast(&mut self) {
        self.toast_message = None;
    }

    pub fn render_topbar(&self) -> String {
        let left = if self.width >= 90 {
            format!(" CONDUCTOR [ NEURONIX v1.0.5:gen-{} ]", self.active_generation)
        } else {
            format!(" CONDUCTOR [ v1.0.5:gen-{} ]", self.active_generation)
        };

        let (t1, t2, t3, t4) = if self.width >= 100 {
            (
                if self.active_tab == WorkspaceTab::Terminal { "[1:Terminal]" } else { "1:Terminal" },
                if self.active_tab == WorkspaceTab::Vital { "[2:Vital]" } else { "2:Vital" },
                if self.active_tab == WorkspaceTab::Proposals { "[3:Proposals]" } else { "3:Proposals" },
                if self.active_tab == WorkspaceTab::Capabilities { "[4:Capabilities]" } else { "4:Capabilities" },
            )
        } else {
            (
                if self.active_tab == WorkspaceTab::Terminal { "[1:Term]" } else { "1:Term" },
                if self.active_tab == WorkspaceTab::Vital { "[2:Vital]" } else { "2:Vital" },
                if self.active_tab == WorkspaceTab::Proposals { "[3:Props]" } else { "3:Props" },
                if self.active_tab == WorkspaceTab::Capabilities { "[4:Skills]" } else { "4:Skills" },
            )
        };
        let tabs = format!(" {} {} {} {} ", t1, t2, t3, t4);

        let health_dot = match self.vital_health_status.as_str() {
            "CRITICAL" => "[!] CRITICAL",
            "DEGRADED" => "[~] DEGRADED",
            _ => "o NOMINAL",
        };
        let right = format!("VITAL {} ", health_dot);

        let total_content = left.len() + tabs.len() + right.len();
        if total_content <= self.width {
            let space_len = self.width - total_content;
            let left_pad = space_len / 2;
            let right_pad = space_len - left_pad;
            format!("{}{}{}{}{}", left, " ".repeat(left_pad), tabs, " ".repeat(right_pad), right)
        } else {
            let space_len = self.width.saturating_sub(left.len() + right.len());
            format!("{}{}{}", left, " ".repeat(space_len), right)
        }
    }

    pub fn show_proposal(&mut self, card: ProposalCard) {
        self.active_overlay = Some(OverlayType::SkillProposal(card));
    }

    pub fn dismiss_overlay(&mut self) {
        self.active_overlay = None;
    }

    pub fn render_frame(&self) -> Vec<String> {
        let mut frame = Vec::with_capacity(self.height);

        // Row 0: Topbar
        frame.push(self.render_topbar());

        // Body rows depending on active tab
        let body_rows = match self.active_tab {
            WorkspaceTab::Terminal => self.render_terminal_body(),
            WorkspaceTab::Vital => self.render_vital_tab(),
            WorkspaceTab::Proposals => self.render_proposals_tab(),
            WorkspaceTab::Capabilities => self.render_capabilities_tab(),
        };

        frame.extend(body_rows);

        // Slide-over overlay injection if present (only when on Terminal tab)
        if self.active_tab == WorkspaceTab::Terminal {
            if let Some(OverlayType::SkillProposal(ref prop)) = self.active_overlay {
                let card_width = 46.min(self.width.saturating_sub(4));
                let start_col = self.width.saturating_sub(card_width + 2);
                let inner_width = card_width.saturating_sub(4);
                let card_lines = vec![
                    format!("+{} +", "-".repeat(card_width - 2)),
                    format!("| PROPOSAL: {:<w$} |", prop.title.chars().take(inner_width.saturating_sub(10)).collect::<String>(), w = inner_width.saturating_sub(10)),
                    format!("| Skill:    {:<w$} |", prop.skill_id.chars().take(inner_width.saturating_sub(10)).collect::<String>(), w = inner_width.saturating_sub(10)),
                    format!("| Severity: {:<w$} |", prop.severity.chars().take(inner_width.saturating_sub(10)).collect::<String>(), w = inner_width.saturating_sub(10)),
                    format!("| Hash:     {:<w$} |", &prop.proposal_hash[..16.min(prop.proposal_hash.len())], w = inner_width.saturating_sub(10)),
                    format!("| Reason:   {:<w$} |", prop.explanation.chars().take(inner_width.saturating_sub(10)).collect::<String>(), w = inner_width.saturating_sub(10)),
                    format!("+{} +", "-".repeat(card_width - 2)),
                    format!("| [y] Approve  [n] Reject  [Esc] Dismiss{:spacer$}|", "", spacer = card_width.saturating_sub(42)),
                    format!("+{} +", "-".repeat(card_width - 2)),
                ];

                for (idx, cline) in card_lines.iter().enumerate() {
                    let target_row = idx + 2;
                    if target_row < frame.len() {
                        let orig = &frame[target_row];
                        let mut prefix = orig.chars().take(start_col).collect::<String>();
                        if prefix.len() < start_col {
                            prefix.push_str(&" ".repeat(start_col - prefix.len()));
                        }
                        frame[target_row] = format!("{}{}", prefix, cline);
                    }
                }
            }
        }

        // Optional bottom toast
        if let Some(ref toast) = self.toast_message {
            if let Some(last_line) = frame.last_mut() {
                let badge = format!(" [!] {} ", toast);
                if badge.len() < self.width {
                    let start = self.width - badge.len() - 2;
                    let mut prefix = last_line.chars().take(start).collect::<String>();
                    if prefix.len() < start {
                        prefix.push_str(&" ".repeat(start - prefix.len()));
                    }
                    *last_line = format!("{}{}", prefix, badge);
                }
            }
        }

        frame
    }

    fn render_terminal_body(&self) -> Vec<String> {
        let mut lines = Vec::with_capacity(self.terminal.rows);
        for r in 0..self.terminal.rows {
            let mut line = self.terminal.line_to_string(r);
            if line.len() < self.width {
                line.push_str(&" ".repeat(self.width - line.len()));
            } else if line.len() > self.width {
                line.truncate(self.width);
            }
            lines.push(line);
        }
        lines
    }

    fn render_vital_tab(&self) -> Vec<String> {
        let term_rows = self.height.saturating_sub(1);
        let mut lines = Vec::with_capacity(term_rows);

        lines.push(self.format_line(""));
        lines.push(self.format_line("  NEURONIX VITAL: Machine Observation Laboratory"));
        lines.push(self.format_line("  ================================================================"));
        lines.push(self.format_line(""));

        let gen_str = if let Some(ref data) = self.vital_data {
            if let Some(gen) = data.nixos_generation {
                format!("NixOS Gen #{} [OBSERVED]", gen)
            } else {
                format!("NixOS Gen #{} [DEFAULT]", self.active_generation)
            }
        } else {
            format!("NixOS Gen #{} [DEFAULT]", self.active_generation)
        };
        lines.push(self.format_line(&format!("    System Generation:     {}", gen_str)));
        lines.push(self.format_line(&format!("    Health Status:         {} [OBSERVED]", self.vital_health_status)));

        if let Some(ref data) = self.vital_data {
            if let Some(ref sr) = data.state_root_digest {
                lines.push(self.format_line(&format!("    StateRoot Commitment:  VALID [OBSERVED: {}..]", &sr[..8.min(sr.len())])));
            } else {
                lines.push(self.format_line("    StateRoot Commitment:  UNAVAILABLE (State engine offline)"));
            }

            let d_stat = data.daemon_status.as_deref().unwrap_or("OFFLINE");
            lines.push(self.format_line(&format!("    AST Socket:            /run/neuronix/ast.sock [{}]", d_stat)));
            lines.push(self.format_line("    Conductor Broker:      Active (Zero-Idle Socket-Activated)"));
            lines.push(self.format_line(""));
            lines.push(self.format_line("  [ Subsystems & Sensors: Live Telemetry ]"));

            if let Some(ref load) = data.cpu_load {
                lines.push(self.format_line(&format!("    CPU Load:              {} [OBSERVED]", load)));
            } else {
                lines.push(self.format_line("    CPU Load:              UNAVAILABLE (Sensor offline)"));
            }

            if let Some(ref mem) = data.memory_info {
                lines.push(self.format_line(&format!("    Memory Usage:          {} [OBSERVED]", mem)));
            } else {
                lines.push(self.format_line("    Memory Usage:          UNAVAILABLE (Sensor offline)"));
            }

            if let Some(temp) = data.cpu_temp_celsius {
                lines.push(self.format_line(&format!("    Thermal Sensor:        {:.1} C [OBSERVED]", temp)));
            } else {
                lines.push(self.format_line("    Thermal Sensor:        UNAVAILABLE (Sensor offline)"));
            }

            if let Some(ref virt) = data.virtualization {
                lines.push(self.format_line(&format!("    Virtualization:        {} [OBSERVED]", virt)));
            } else {
                lines.push(self.format_line("    Virtualization:        UNAVAILABLE (DMI offline)"));
            }
        } else {
            lines.push(self.format_line("    StateRoot Commitment:  UNAVAILABLE (Control socket not connected)"));
            lines.push(self.format_line("    AST Socket:            /run/neuronix/ast.sock [DISCONNECTED]"));
            lines.push(self.format_line("    Conductor Broker:      Active (Zero-Idle Socket-Activated)"));
            lines.push(self.format_line(""));
            lines.push(self.format_line("  [ Subsystems & Sensors: Live Telemetry ]"));
            lines.push(self.format_line("    CPU Load:              UNAVAILABLE (Awaiting runtime telemetry)"));
            lines.push(self.format_line("    Memory Usage:          UNAVAILABLE (Awaiting runtime telemetry)"));
            lines.push(self.format_line("    Thermal Sensor:        UNAVAILABLE (Awaiting runtime telemetry)"));
            lines.push(self.format_line("    Virtualization:        UNAVAILABLE (Awaiting runtime telemetry)"));
        }

        lines.push(self.format_line(""));
        lines.push(self.format_line("  Press [1] to return to Terminal Canvas"));

        while lines.len() < term_rows {
            lines.push(self.format_line(""));
        }
        lines
    }

    fn render_proposals_tab(&self) -> Vec<String> {
        let term_rows = self.height.saturating_sub(1);
        let mut lines = Vec::with_capacity(term_rows);

        lines.push(self.format_line(""));
        lines.push(self.format_line("  USER SOVEREIGNTY: Capability Proposal Resolution Deck"));
        lines.push(self.format_line("  ================================================================"));
        lines.push(self.format_line("  AI agents may propose mutations. Only the human user may resolve them."));
        lines.push(self.format_line(""));

        if let Some(OverlayType::SkillProposal(ref prop)) = self.active_overlay {
            lines.push(self.format_line("  [ ACTIVE PROPOSAL REQUIRING DECISION ]"));
            lines.push(self.format_line(&format!("    Title:        {}", prop.title)));
            lines.push(self.format_line(&format!("    Skill:        {}", prop.skill_id)));
            lines.push(self.format_line(&format!("    Severity:     {}", prop.severity)));
            lines.push(self.format_line(&format!("    Hash:         {}", prop.proposal_hash)));
            lines.push(self.format_line(&format!("    Explanation:  {}", prop.explanation)));
            lines.push(self.format_line(""));
            lines.push(self.format_line("    Actions:      [y] APPROVE (Issue execution grant)   [n] REJECT (Discard)"));
            lines.push(self.format_line(""));
        } else {
            lines.push(self.format_line("  No pending proposals requiring human sovereign approval."));
            lines.push(self.format_line("  System is currently in a steady-state quiescent condition."));
            lines.push(self.format_line(""));
        }

        lines.push(self.format_line("  Press [1] for Terminal, [2] for Vital, [4] for Capabilities"));

        while lines.len() < term_rows {
            lines.push(self.format_line(""));
        }
        lines
    }

    fn render_capabilities_tab(&self) -> Vec<String> {
        let term_rows = self.height.saturating_sub(1);
        let mut lines = Vec::with_capacity(term_rows);

        lines.push(self.format_line(""));
        lines.push(self.format_line("  CONDUCTOR CAPABILITY REGISTRY: Universal Skills"));
        lines.push(self.format_line("  ================================================================"));
        lines.push(self.format_line(""));
        lines.push(self.format_line("  [ Mutation Skills: Approval Gate MANDATORY ]"));
        lines.push(self.format_line("    - system.upgrade     Perform atomic declarative NixOS upgrade"));
        lines.push(self.format_line("    - system.rollback    Revert system generation atomically"));
        lines.push(self.format_line("    - storage.plan       Deterministic btrfs subvolume layout"));
        lines.push(self.format_line(""));
        lines.push(self.format_line("  [ Inspection & Execution Skills: Read-Only / Controlled ]"));
        lines.push(self.format_line("    - system.status      Comprehensive host platform metadata"));
        lines.push(self.format_line("    - state.verify       Cryptographic StateRoot & passport verification"));
        lines.push(self.format_line("    - boot.verify        Measured boot & UKI tamper attestation"));
        lines.push(self.format_line("    - hyperion.run       Deterministic workload sandboxing (Tier 0-3)"));
        lines.push(self.format_line("    - daemon.status      Query micro-Rust daemon socket health"));
        lines.push(self.format_line("    - package.verify     Verify integrity of /nix/store derivations"));
        lines.push(self.format_line(""));
        lines.push(self.format_line("  Press [1] to return to Terminal Canvas"));

        while lines.len() < term_rows {
            lines.push(self.format_line(""));
        }
        lines
    }

    fn format_line(&self, text: &str) -> String {
        if text.len() < self.width {
            format!("{}{}", text, " ".repeat(self.width - text.len()))
        } else {
            text.chars().take(self.width).collect()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_topbar_rendering() {
        let layout = SurfaceLayout::new(80, 24);
        let topbar = layout.render_topbar();
        assert!(topbar.contains("CONDUCTOR [ v1.0.5"));
        assert!(topbar.contains("1:Term"));
        assert!(topbar.contains("VITAL o NOMINAL"));
        assert_eq!(topbar.len(), 80);

        let wide_layout = SurfaceLayout::new(120, 24);
        let wide_topbar = wide_layout.render_topbar();
        assert!(wide_topbar.contains("CONDUCTOR [ NEURONIX v1.0.5"));
        assert!(wide_topbar.contains("1:Terminal"));
        assert_eq!(wide_topbar.len(), 120);
    }

    #[test]
    fn test_overlay_rendering() {
        let mut layout = SurfaceLayout::new(80, 24);
        layout.terminal.write_str("Line 1 in terminal\nLine 2 in terminal\nLine 3");
        layout.show_proposal(ProposalCard {
            title: "Generation Rollback".to_string(),
            skill_id: "system.rollback".to_string(),
            severity: "WARNING".to_string(),
            proposal_hash: "1234567890abcdef".to_string(),
            explanation: "Rollback to gen 41".to_string(),
        });

        let frame = layout.render_frame();
        assert_eq!(frame.len(), 24);
        assert!(frame[0].contains("CONDUCTOR"));
        assert!(frame[3].contains("PROPOSAL: Generation"));
        assert!(frame[9].contains("[y] Approve"));
    }

    #[test]
    fn test_tab_switching() {
        let mut layout = SurfaceLayout::new(80, 24);
        assert_eq!(layout.active_tab, WorkspaceTab::Terminal);

        layout.set_tab(WorkspaceTab::Vital);
        let frame_vital = layout.render_frame();
        assert!(frame_vital[2].contains("NEURONIX VITAL"));

        layout.set_tab(WorkspaceTab::Proposals);
        let frame_prop = layout.render_frame();
        assert!(frame_prop[2].contains("USER SOVEREIGNTY"));

        layout.set_tab(WorkspaceTab::Capabilities);
        let frame_cap = layout.render_frame();
        assert!(frame_cap[2].contains("CONDUCTOR CAPABILITY REGISTRY"));
    }
}
