use crate::config::*;
use std::env;
use std::io::Write;
use std::process::{Command, Stdio};

fn entry(value: &str, info: &str, disabled: bool) {
    let safe: String = value
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    println!(
        "{safe}\0info\x1f{info}{}",
        if disabled {
            "\x1fnonselectable\x1ftrue\x1fpermanent\x1ftrue"
        } else {
            ""
        }
    );
}

fn header(key: &str, value: &str) {
    println!("\0{key}\x1f{value}");
}

pub fn clipboard_mode() -> Result {
    let get = |name| env::var(name).unwrap_or_default();
    let action = get("ROFI_RETV");
    let state = get("ROFI_DATA");
    let info = get("ROFI_INFO");

    header("no-custom", "true");
    header("use-hot-keys", "true");
    header("keep-selection", "true");

    // Action 1: User selected an item -> decode and copy to clipboard
    if action == "1" && !info.is_empty() {
        if let Ok(raw) = hex::decode(&info) {
            let mut child = Command::new("cliphist")
                .arg("decode")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()?;
            if let Some(mut stdin) = child.stdin.take() {
                stdin.write_all(&raw)?;
            }
            if let Ok(output) = child.wait_with_output() {
                let mut wl = Command::new("wl-copy").stdin(Stdio::piped()).spawn()?;
                if let Some(mut stdin) = wl.stdin.take() {
                    stdin.write_all(&output.stdout)?;
                }
                let _ = wl.wait();
            }
        }
        std::process::exit(0);
    }

    // Action 10: Shift+Delete -> delete specific entry
    if action == "10" && !info.is_empty() {
        if let Ok(raw) = hex::decode(&info) {
            let mut child = Command::new("cliphist")
                .arg("delete")
                .stdin(Stdio::piped())
                .spawn()?;
            if let Some(mut stdin) = child.stdin.take() {
                stdin.write_all(&raw)?;
            }
            let _ = child.wait();
        }
    }

    // Action 11: Ctrl+Shift+Delete -> Wipe history confirmation
    if action == "11" {
        header("prompt", "Wipe clipboard history?");
        header("data", "confirm");
        entry("Yes, wipe all clipboard history", "confirm-wipe", false);
        entry("Cancel", "cancel", false);
        return Ok(());
    }

    if state == "confirm" {
        if action == "1" && info == "confirm-wipe" {
            let _ = Command::new("cliphist").arg("wipe").status();
            std::process::exit(0);
        }
    }

    // Render clipboard history
    header("prompt", "Clipboard");
    header("data", "history");

    if let Ok(o) = Command::new("cliphist").arg("list").output() {
        if o.stdout.is_empty() {
            entry("Clipboard is empty", "", true);
        } else {
            for row in o.stdout.split(|c| *c == b'\n').filter(|r| !r.is_empty()) {
                if let Some(tab) = row.iter().position(|c| *c == b'\t') {
                    let display_text = String::from_utf8_lossy(&row[tab + 1..]);
                    let raw_hex = hex::encode(row);
                    entry(&display_text, &raw_hex, false);
                }
            }
        }
    }

    Ok(())
}

// Simple hex encoder/decoder avoiding heavy base64 dependency
mod hex {
    pub fn encode(data: &[u8]) -> String {
        data.iter().map(|b| format!("{:02x}", b)).collect()
    }

    pub fn decode(s: &str) -> Result<Vec<u8>, ()> {
        if s.len() % 2 != 0 {
            return Err(());
        }
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| ()))
            .collect()
    }
}
