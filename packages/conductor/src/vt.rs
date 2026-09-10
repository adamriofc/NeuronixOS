// ==============================================================================
// NEURONIX Conductor Terminal Subsystem: VT100 / ANSI Terminal State Machine
// Provides memory-safe terminal screen buffers, cursor management, and SGR parser.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

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
    Rgb(u8, u8, u8),
}

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

    pub fn write_str(&mut self, s: &str) {
        let mut chars = s.chars().peekable();
        while let Some(ch) = chars.next() {
            if ch == '\x1b' {
                if let Some(&'[') = chars.peek() {
                    chars.next(); // Consume '['
                    let mut seq = String::new();
                    while let Some(&next_c) = chars.peek() {
                        if next_c.is_ascii_alphabetic() || next_c == '?' {
                            seq.push(chars.next().unwrap());
                            if next_c.is_ascii_alphabetic() {
                                break;
                            }
                        } else if next_c.is_ascii_digit() || next_c == ';' {
                            seq.push(chars.next().unwrap());
                        } else {
                            break;
                        }
                    }
                    self.handle_csi(&seq);
                    continue;
                }
            }
            self.put_char(ch);
        }
    }

    fn handle_csi(&mut self, seq: &str) {
        if seq.ends_with('m') {
            // SGR
            let params = &seq[..seq.len() - 1];
            if params.is_empty() {
                self.reset_attributes();
                return;
            }
            for part in params.split(';') {
                match part.parse::<u16>().unwrap_or(0) {
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
                    39 => self.current_fg = Color::Default,
                    40 => self.current_bg = Color::Black,
                    41 => self.current_bg = Color::Red,
                    42 => self.current_bg = Color::Green,
                    43 => self.current_bg = Color::Yellow,
                    44 => self.current_bg = Color::Blue,
                    45 => self.current_bg = Color::Magenta,
                    46 => self.current_bg = Color::Cyan,
                    47 => self.current_bg = Color::White,
                    49 => self.current_bg = Color::Default,
                    _ => {}
                }
            }
        } else if seq.ends_with('H') || seq.ends_with('f') {
            // Cursor position
            let body = &seq[..seq.len() - 1];
            let parts: Vec<&str> = body.split(';').collect();
            let row = parts.get(0).and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            let col = parts.get(1).and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            self.cursor_row = (row.saturating_sub(1)).min(self.rows - 1);
            self.cursor_col = (col.saturating_sub(1)).min(self.cols - 1);
        } else if seq.ends_with('J') {
            let mode = seq[..seq.len() - 1].parse::<u8>().unwrap_or(0);
            if mode == 2 {
                self.clear_screen();
            }
        } else if seq.ends_with('K') {
            let mode = seq[..seq.len() - 1].parse::<u8>().unwrap_or(0);
            self.clear_line(mode);
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
}
