// ==============================================================================
// NEURONIX Conductor Terminal Subsystem: VT100 / ANSI Terminal State Machine
// Provides memory-safe terminal screen buffers, cursor management, and SGR parser.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

/// VT100 and ANSI terminal color representation.
/// Supports standard 16 colors, 256 indexed palette, and 24-bit RGB truecolor.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Color {
    Default,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    BrightBlack,
    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    BrightWhite,
    Indexed(u8),
    Rgb(u8, u8, u8),
}

/// A single terminal cell representing character glyph and visual attributes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cell {
    pub ch: char,
    pub fg: Color,
    pub bg: Color,
    pub bold: bool,
    pub underline: bool,
    pub inverse: bool,
}

impl Default for Cell {
    fn default() -> Self {
        Cell {
            ch: ' ',
            fg: Color::Default,
            bg: Color::Default,
            bold: false,
            underline: false,
            inverse: false,
        }
    }
}

/// VT100 terminal screen buffer with cursor state and scrollback history.
#[derive(Debug)]
pub struct TerminalBuffer {
    pub cols: usize,
    pub rows: usize,
    pub cursor_row: usize,
    pub cursor_col: usize,
    pub grid: Vec<Vec<Cell>>,
    pub scrollback: Vec<Vec<Cell>>,
    pub in_alternate_screen: bool,
    saved_cursor: (usize, usize),
    current_fg: Color,
    current_bg: Color,
    current_bold: bool,
    current_underline: bool,
    current_inverse: bool,
}

impl TerminalBuffer {
    pub fn new(cols: usize, rows: usize) -> Self {
        let actual_cols = cols.max(1);
        let actual_rows = rows.max(1);
        let grid = vec![vec![Cell::default(); actual_cols]; actual_rows];
        TerminalBuffer {
            cols: actual_cols,
            rows: actual_rows,
            cursor_row: 0,
            cursor_col: 0,
            grid,
            scrollback: Vec::new(),
            in_alternate_screen: false,
            saved_cursor: (0, 0),
            current_fg: Color::Default,
            current_bg: Color::Default,
            current_bold: false,
            current_underline: false,
            current_inverse: false,
        }
    }

    #[allow(clippy::needless_range_loop)]
    pub fn resize(&mut self, new_cols: usize, new_rows: usize) {
        let new_cols = new_cols.max(1);
        let new_rows = new_rows.max(1);
        let mut new_grid = vec![vec![Cell::default(); new_cols]; new_rows];

        for r in 0..self.rows.min(new_rows) {
            for c in 0..self.cols.min(new_cols) {
                new_grid[r][c] = self.grid[r][c];
            }
        }

        self.cols = new_cols;
        self.rows = new_rows;
        self.grid = new_grid;
        self.cursor_row = self.cursor_row.min(new_rows - 1);
        self.cursor_col = self.cursor_col.min(new_cols - 1);
    }

    pub fn put_char(&mut self, ch: char) {
        match ch {
            '\r' => {
                self.cursor_col = 0;
            }
            '\n' => {
                self.cursor_col = 0;
                self.new_line();
            }
            '\t' => {
                let next_tab = (self.cursor_col / 8 + 1) * 8;
                self.cursor_col = next_tab.min(self.cols - 1);
            }
            '\x08' => {
                if self.cursor_col > 0 {
                    self.cursor_col -= 1;
                }
            }
            c if c >= ' ' => {
                if self.cursor_col >= self.cols {
                    self.cursor_col = 0;
                    self.new_line();
                }
                if self.cursor_row < self.rows && self.cursor_col < self.cols {
                    self.grid[self.cursor_row][self.cursor_col] = Cell {
                        ch: c,
                        fg: self.current_fg,
                        bg: self.current_bg,
                        bold: self.current_bold,
                        underline: self.current_underline,
                        inverse: self.current_inverse,
                    };
                    self.cursor_col += 1;
                }
            }
            _ => {}
        }
    }

    fn new_line(&mut self) {
        if self.cursor_row + 1 < self.rows {
            self.cursor_row += 1;
        } else {
            // Scroll down
            if !self.in_alternate_screen && !self.grid.is_empty() {
                self.scrollback.push(self.grid[0].clone());
                if self.scrollback.len() > 5000 {
                    self.scrollback.remove(0);
                }
            }
            self.grid.remove(0);
            self.grid.push(vec![Cell::default(); self.cols]);
        }
    }

    pub fn clear_screen(&mut self) {
        for r in 0..self.rows {
            for c in 0..self.cols {
                self.grid[r][c] = Cell::default();
            }
        }
        self.cursor_row = 0;
        self.cursor_col = 0;
    }

    pub fn clear_line(&mut self, mode: u8) {
        if self.cursor_row >= self.rows {
            return;
        }
        match mode {
            0 => {
                // Cursor to end
                for c in self.cursor_col..self.cols {
                    self.grid[self.cursor_row][c] = Cell::default();
                }
            }
            1 => {
                // Start to cursor
                for c in 0..=self.cursor_col.min(self.cols - 1) {
                    self.grid[self.cursor_row][c] = Cell::default();
                }
            }
            2 => {
                // Entire line
                for c in 0..self.cols {
                    self.grid[self.cursor_row][c] = Cell::default();
                }
            }
            _ => {}
        }
    }

    pub fn write_bytes(&mut self, bytes: &[u8]) {
        let text = String::from_utf8_lossy(bytes);
        self.write_str(&text);
    }

    pub fn save_cursor(&mut self) {
        self.saved_cursor = (self.cursor_row, self.cursor_col);
    }

    pub fn restore_cursor(&mut self) {
        self.cursor_row = self.saved_cursor.0.min(self.rows - 1);
        self.cursor_col = self.saved_cursor.1.min(self.cols - 1);
    }

    pub fn write_str(&mut self, s: &str) {
        let mut chars = s.chars().peekable();
        while let Some(ch) = chars.next() {
            if ch == '\x1b' {
                if let Some(&next_c) = chars.peek() {
                    if next_c == '[' {
                        chars.next(); // Consume '['
                        let mut seq = String::new();
                        while let Some(&cmd_c) = chars.peek() {
                            if cmd_c.is_ascii_alphabetic() || cmd_c == '?' || cmd_c == '@' {
                                seq.push(chars.next().unwrap());
                                if cmd_c.is_ascii_alphabetic() || cmd_c == '@' {
                                    break;
                                }
                            } else if cmd_c.is_ascii_digit() || cmd_c == ';' {
                                seq.push(chars.next().unwrap());
                            } else {
                                break;
                            }
                        }
                        self.handle_csi(&seq);
                        continue;
                    } else if next_c == '7' {
                        chars.next(); // Consume '7' (DECSC)
                        self.save_cursor();
                        continue;
                    } else if next_c == '8' {
                        chars.next(); // Consume '8' (DECRC)
                        self.restore_cursor();
                        continue;
                    }
                }
            }
            self.put_char(ch);
        }
    }

    fn handle_csi(&mut self, seq: &str) {
        if let Some(params) = seq.strip_suffix('m') {
            // SGR
            if params.is_empty() {
                self.reset_attributes();
                return;
            }
            let tokens: Vec<&str> = params.split(';').collect();
            let mut i = 0;
            while i < tokens.len() {
                let code = tokens[i].parse::<u16>().unwrap_or(0);
                match code {
                    0 => self.reset_attributes(),
                    1 => self.current_bold = true,
                    4 => self.current_underline = true,
                    7 => self.current_inverse = true,
                    22 => self.current_bold = false,
                    24 => self.current_underline = false,
                    27 => self.current_inverse = false,
                    30 => self.current_fg = Color::Black,
                    31 => self.current_fg = Color::Red,
                    32 => self.current_fg = Color::Green,
                    33 => self.current_fg = Color::Yellow,
                    34 => self.current_fg = Color::Blue,
                    35 => self.current_fg = Color::Magenta,
                    36 => self.current_fg = Color::Cyan,
                    37 => self.current_fg = Color::White,
                    38 => {
                        // Extended foreground: 38;5;n or 38;2;r;g;b
                        if i + 2 < tokens.len() && tokens[i + 1] == "5" {
                            if let Ok(n) = tokens[i + 2].parse::<u8>() {
                                self.current_fg = Color::Indexed(n);
                            }
                            i += 2;
                        } else if i + 4 < tokens.len() && tokens[i + 1] == "2" {
                            if let (Ok(r), Ok(g), Ok(b)) = (
                                tokens[i + 2].parse::<u8>(),
                                tokens[i + 3].parse::<u8>(),
                                tokens[i + 4].parse::<u8>(),
                            ) {
                                self.current_fg = Color::Rgb(r, g, b);
                            }
                            i += 4;
                        }
                    }
                    39 => self.current_fg = Color::Default,
                    40 => self.current_bg = Color::Black,
                    41 => self.current_bg = Color::Red,
                    42 => self.current_bg = Color::Green,
                    43 => self.current_bg = Color::Yellow,
                    44 => self.current_bg = Color::Blue,
                    45 => self.current_bg = Color::Magenta,
                    46 => self.current_bg = Color::Cyan,
                    47 => self.current_bg = Color::White,
                    48 => {
                        // Extended background: 48;5;n or 48;2;r;g;b
                        if i + 2 < tokens.len() && tokens[i + 1] == "5" {
                            if let Ok(n) = tokens[i + 2].parse::<u8>() {
                                self.current_bg = Color::Indexed(n);
                            }
                            i += 2;
                        } else if i + 4 < tokens.len() && tokens[i + 1] == "2" {
                            if let (Ok(r), Ok(g), Ok(b)) = (
                                tokens[i + 2].parse::<u8>(),
                                tokens[i + 3].parse::<u8>(),
                                tokens[i + 4].parse::<u8>(),
                            ) {
                                self.current_bg = Color::Rgb(r, g, b);
                            }
                            i += 4;
                        }
                    }
                    49 => self.current_bg = Color::Default,
                    90 => self.current_fg = Color::BrightBlack,
                    91 => self.current_fg = Color::BrightRed,
                    92 => self.current_fg = Color::BrightGreen,
                    93 => self.current_fg = Color::BrightYellow,
                    94 => self.current_fg = Color::BrightBlue,
                    95 => self.current_fg = Color::BrightMagenta,
                    96 => self.current_fg = Color::BrightCyan,
                    97 => self.current_fg = Color::BrightWhite,
                    100 => self.current_bg = Color::BrightBlack,
                    101 => self.current_bg = Color::BrightRed,
                    102 => self.current_bg = Color::BrightGreen,
                    103 => self.current_bg = Color::BrightYellow,
                    104 => self.current_bg = Color::BrightBlue,
                    105 => self.current_bg = Color::BrightMagenta,
                    106 => self.current_bg = Color::BrightCyan,
                    107 => self.current_bg = Color::BrightWhite,
                    _ => {}
                }
                i += 1;
            }
        } else if let Some(body) = seq.strip_suffix('H').or_else(|| seq.strip_suffix('f')) {
            // Cursor position
            let parts: Vec<&str> = body.split(';').collect();
            let row = parts.first().and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            let col = parts.get(1).and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            self.cursor_row = (row.saturating_sub(1)).min(self.rows - 1);
            self.cursor_col = (col.saturating_sub(1)).min(self.cols - 1);
        } else if let Some(stripped) = seq.strip_suffix('J') {
            let mode = stripped.parse::<u8>().unwrap_or(0);
            if mode == 2 {
                self.clear_screen();
            }
        } else if let Some(stripped) = seq.strip_suffix('K') {
            let mode = stripped.parse::<u8>().unwrap_or(0);
            self.clear_line(mode);
        } else if let Some(stripped) = seq.strip_suffix('A') {
            // Cursor Up
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            self.cursor_row = self.cursor_row.saturating_sub(n);
        } else if let Some(stripped) = seq.strip_suffix('B') {
            // Cursor Down
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            self.cursor_row = (self.cursor_row + n).min(self.rows - 1);
        } else if let Some(stripped) = seq.strip_suffix('C') {
            // Cursor Forward
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            self.cursor_col = (self.cursor_col + n).min(self.cols - 1);
        } else if let Some(stripped) = seq.strip_suffix('D') {
            // Cursor Backward
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            self.cursor_col = self.cursor_col.saturating_sub(n);
        } else if let Some(stripped) = seq.strip_suffix('G') {
            // Cursor Horizontal Absolute
            let col = stripped.parse::<usize>().unwrap_or(1);
            self.cursor_col = (col.saturating_sub(1)).min(self.cols - 1);
        } else if let Some(stripped) = seq.strip_suffix('L') {
            // Insert Line
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            for _ in 0..n {
                if self.cursor_row < self.rows {
                    self.grid.insert(self.cursor_row, vec![Cell::default(); self.cols]);
                    self.grid.truncate(self.rows);
                }
            }
        } else if let Some(stripped) = seq.strip_suffix('M') {
            // Delete Line
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            for _ in 0..n {
                if self.cursor_row < self.rows {
                    self.grid.remove(self.cursor_row);
                    self.grid.push(vec![Cell::default(); self.cols]);
                }
            }
        } else if let Some(stripped) = seq.strip_suffix('@') {
            // Insert Characters
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            if self.cursor_row < self.rows {
                for _ in 0..n {
                    if self.cursor_col < self.cols {
                        self.grid[self.cursor_row].insert(self.cursor_col, Cell::default());
                        self.grid[self.cursor_row].truncate(self.cols);
                    }
                }
            }
        } else if let Some(stripped) = seq.strip_suffix('P') {
            // Delete Characters
            let n = stripped.parse::<usize>().unwrap_or(1).max(1);
            if self.cursor_row < self.rows {
                for _ in 0..n {
                    if self.cursor_col < self.cols {
                        self.grid[self.cursor_row].remove(self.cursor_col);
                        self.grid[self.cursor_row].push(Cell::default());
                    }
                }
            }
        } else if seq == "s" || (seq.ends_with('s') && !seq.starts_with('?')) {
            // Cursor Save (ANSI.SYS)
            self.save_cursor();
        } else if seq == "u" || (seq.ends_with('u') && !seq.starts_with('?')) {
            // Cursor Restore (ANSI.SYS)
            self.restore_cursor();
        } else if seq == "?1049h" {
            self.in_alternate_screen = true;
            self.saved_cursor = (self.cursor_row, self.cursor_col);
            self.clear_screen();
        } else if seq == "?1049l" {
            self.in_alternate_screen = false;
            self.cursor_row = self.saved_cursor.0.min(self.rows - 1);
            self.cursor_col = self.saved_cursor.1.min(self.cols - 1);
        }
    }

    fn reset_attributes(&mut self) {
        self.current_fg = Color::Default;
        self.current_bg = Color::Default;
        self.current_bold = false;
        self.current_underline = false;
        self.current_inverse = false;
    }

    pub fn line_to_string(&self, row: usize) -> String {
        if row >= self.rows {
            return String::new();
        }
        self.grid[row].iter().map(|c| c.ch).collect::<String>().trim_end().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_buffer_creation_and_text_write() {
        let mut term = TerminalBuffer::new(80, 24);
        term.write_str("Hello NEURONIX Conductor!\nSecond line.");
        assert_eq!(term.line_to_string(0), "Hello NEURONIX Conductor!");
        assert_eq!(term.line_to_string(1), "Second line.");
    }

    #[test]
    fn test_ansi_color_and_clear() {
        let mut term = TerminalBuffer::new(40, 10);
        term.write_str("\x1b[31;1mRed Bold Text\x1b[0m Normal");
        assert_eq!(term.line_to_string(0), "Red Bold Text Normal");
        assert_eq!(term.grid[0][0].fg, Color::Red);
        assert!(term.grid[0][0].bold);
        assert_eq!(term.grid[0][14].fg, Color::Default);
        assert!(!term.grid[0][14].bold);

        // Clear screen
        term.write_str("\x1b[2J");
        assert_eq!(term.line_to_string(0), "");
        assert_eq!(term.cursor_row, 0);
        assert_eq!(term.cursor_col, 0);
    }

    #[test]
    fn test_cursor_movement_and_erasing() {
        let mut term = TerminalBuffer::new(40, 10);
        term.write_str("\x1b[5;10HTarget");
        assert_eq!(term.cursor_row, 4);
        assert_eq!(term.cursor_col, 15);
        assert_eq!(term.grid[4][9].ch, 'T');
        assert_eq!(term.grid[4][14].ch, 't');

        // Erase line from cursor
        term.write_str("\x1b[K");
        assert_eq!(term.grid[4][15].ch, ' ');
    }

    #[test]
    fn test_extended_256_and_truecolor() {
        let mut term = TerminalBuffer::new(40, 10);
        // 256-color foreground (color 208: orange) and background (color 236: dark grey)
        term.write_str("\x1b[38;5;208;48;5;236m256Color\x1b[0m");
        assert_eq!(term.grid[0][0].fg, Color::Indexed(208));
        assert_eq!(term.grid[0][0].bg, Color::Indexed(236));

        // TrueColor foreground (r:123, g:45, b:67) and background (r:10, g:20, b:30)
        term.write_str("\x1b[38;2;123;45;67;48;2;10;20;30mTrueColor\x1b[0m");
        assert_eq!(term.grid[0][8].fg, Color::Rgb(123, 45, 67));
        assert_eq!(term.grid[0][8].bg, Color::Rgb(10, 20, 30));
    }

    #[test]
    fn test_relative_cursor_movement() {
        let mut term = TerminalBuffer::new(40, 10);
        term.write_str("\x1b[5;5H"); // row 4, col 4
        assert_eq!(term.cursor_row, 4);
        assert_eq!(term.cursor_col, 4);

        term.write_str("\x1b[2A"); // Up 2 -> row 2
        assert_eq!(term.cursor_row, 2);

        term.write_str("\x1b[3B"); // Down 3 -> row 5
        assert_eq!(term.cursor_row, 5);

        term.write_str("\x1b[4C"); // Right 4 -> col 8
        assert_eq!(term.cursor_col, 8);

        term.write_str("\x1b[2D"); // Left 2 -> col 6
        assert_eq!(term.cursor_col, 6);

        term.write_str("\x1b[10G"); // Col 10 (1-based, index 9)
        assert_eq!(term.cursor_col, 9);
    }

    #[test]
    fn test_cursor_save_and_restore() {
        let mut term = TerminalBuffer::new(40, 10);
        term.write_str("\x1b[3;7H\x1b7"); // Save at (2, 6) with ESC 7
        assert_eq!(term.cursor_row, 2);
        assert_eq!(term.cursor_col, 6);

        term.write_str("\x1b[8;20H"); // Move to (7, 19)
        assert_eq!(term.cursor_row, 7);
        assert_eq!(term.cursor_col, 19);

        term.write_str("\x1b8"); // Restore with ESC 8
        assert_eq!(term.cursor_row, 2);
        assert_eq!(term.cursor_col, 6);

        // Also test CSI s / CSI u
        term.write_str("\x1b[s\x1b[1;1H\x1b[u");
        assert_eq!(term.cursor_row, 2);
        assert_eq!(term.cursor_col, 6);
    }

    #[test]
    fn test_line_insert_delete() {
        let mut term = TerminalBuffer::new(40, 5);
        term.write_str("Line0\nLine1\nLine2\nLine3\nLine4");
        assert_eq!(term.line_to_string(1), "Line1");

        // Move to line 1 and insert a blank line
        term.write_str("\x1b[2;1H\x1b[1L");
        assert_eq!(term.line_to_string(1), "");
        assert_eq!(term.line_to_string(2), "Line1");

        // Delete that inserted blank line
        term.write_str("\x1b[2;1H\x1b[1M");
        assert_eq!(term.line_to_string(1), "Line1");
    }

    #[test]
    fn test_char_insert_delete() {
        let mut term = TerminalBuffer::new(40, 5);
        term.write_str("ABCD");
        // Move to col 2 ('B') and insert 2 blank chars
        term.write_str("\x1b[1;2H\x1b[2@");
        assert_eq!(term.line_to_string(0), "A  BCD");

        // Delete the 2 blank chars
        term.write_str("\x1b[1;2H\x1b[2P");
        assert_eq!(term.line_to_string(0), "ABCD");
    }
}
