// ==============================================================================
// NEURONIX Conductor Surface & Workspace Canvas Engine
// Renders the 95% minimalist terminal canvas, subtle topbar, and ephemeral proposal cards.
// Adheres strictly to SPEC-NRX-CND-018 and SPEC-NRX-CND-021.
// ==============================================================================

use crate::vt::TerminalBuffer;

pub struct SurfaceLayout {
    pub width: usize,
    pub height: usize,
    pub terminal: TerminalBuffer,
    pub active_overlay: Option<OverlayType>,
    pub vital_health_status: String,
    pub active_generation: u32,
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
    pub cpu_load: String,
    pub memory_used_pct: f32,
    pub cpu_temp_celsius: Option<f32>,
    pub nixos_generation: u32,
}

impl SurfaceLayout {
    pub fn new(width: usize, height: usize) -> Self {
        let width = width.max(40);
        let height = height.max(10);
        // Reserve 1 row for topbar, remainder for terminal
        let term_rows = height.saturating_sub(1);
        SurfaceLayout {
            width,
            height,
            terminal: TerminalBuffer::new(width, term_rows),
            active_overlay: None,
            vital_health_status: "NOMINAL".to_string(),
            active_generation: 1,
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

    pub fn render_topbar(&self) -> String {
        let left = format!(" CONDUCTOR  [ NEURONIX v1.0.4:gen-{} ]", self.active_generation);
        let health_dot = match self.vital_health_status.as_str() {
            "CRITICAL" => "[!] CRITICAL",
            "DEGRADED" => "[~] DEGRADED",
            _ => "o NOMINAL",
        };
        let right = format!("VITAL {} ", health_dot);

        let space_len = self.width.saturating_sub(left.len() + right.len());
        let spacer = " ".repeat(space_len);
        format!("{}{}{}", left, spacer, right)
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

        // Rows 1..N: Terminal Buffer
        for r in 0..self.terminal.rows {
            let mut line = self.terminal.line_to_string(r);
            if line.len() < self.width {
                line.push_str(&" ".repeat(self.width - line.len()));
            } else if line.len() > self.width {
                line.truncate(self.width);
            }
            frame.push(line);
        }

        // Overlay injection if present (draw on right 50% of the canvas)
        if let Some(OverlayType::SkillProposal(ref prop)) = self.active_overlay {
            let card_width = 44.min(self.width - 4);
            let start_col = self.width.saturating_sub(card_width + 2);
            let card_lines = vec![
                format!("+{} +", "-".repeat(card_width - 2)),
                format!("| PROPOSAL: {:<width$} |", prop.title, width = card_width - 15),
                format!("| Skill:    {:<width$} |", prop.skill_id, width = card_width - 15),
                format!("| Risk:     {:<width$} |", prop.severity, width = card_width - 15),
                format!("| Hash:     {:<width$} |", &prop.proposal_hash[..16.min(prop.proposal_hash.len())], width = card_width - 15),
                format!("| [A]ccept  [R]eject{:spacer$}|", "", spacer = card_width - 21),
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

        frame
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_topbar_rendering() {
        let layout = SurfaceLayout::new(80, 24);
        let topbar = layout.render_topbar();
        assert!(topbar.starts_with(" CONDUCTOR  [ NEURONIX v1.0.4"));
        assert!(topbar.ends_with("VITAL o NOMINAL "));
        assert_eq!(topbar.len(), 80);
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
        assert!(frame[3].contains("PROPOSAL: Generation Rollback"));
    }
}
