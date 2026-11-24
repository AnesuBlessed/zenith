use crate::{config::*, palette, wallpaper};
use std::path::PathBuf;

/// Palette entry points. All rendering lives in `palette.rs` so every consumer
/// (Quickshell, Hyprland, foot, rofi, the picker) sees one atomically written
/// source of truth.
pub fn refresh() -> Result {
    let current = wallpaper::current();
    if current.is_empty() {
        return Err(error("No wallpaper selected yet"));
    }
    palette::regenerate_wallpaper(&PathBuf::from(current))?;
    reload_hyprland();
    println!("PALETTE=updated");
    Ok(())
}

pub fn from_color(color: &str) -> Result {
    let scheme = current_scheme();
    let mode = palette::preferred_mode();
    palette::write_palette(color, &scheme, &mode)?;
    reload_hyprland();
    println!("PALETTE=updated");
    Ok(())
}

pub fn current_scheme() -> String {
    let path = xdg("XDG_CONFIG_HOME", ".config").join("zenith/settings.json");
    if let Ok(raw) = std::fs::read_to_string(path) {
        if let Ok(value) = serde_json::from_str::<serde_json::Value>(&raw) {
            if let Some(name) = value["wallpaper"]["scheme"].as_str() {
                return name.to_string();
            }
        }
    }
    "scheme-content".into()
}

pub fn reload_hyprland() {
    if exists("hyprctl") {
        let _ = run("hyprctl", &["reload"]);
    }
}