mod clipboard;
mod config;
mod theme;
mod wallpaper;
mod wallpaper_align;

use config::*;
use std::{env, path::PathBuf};

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if let Err(e) = dispatch(&args) {
        eprintln!("Zenith-Native Error: {e}");
        std::process::exit(1);
    }
}

fn dispatch(args: &[String]) -> Result {
    let (cmd, rest) = args
        .split_first()
        .map(|(c, r)| (c.as_str(), r))
        .unwrap_or(("help", &[]));

    match cmd {
        "clipboard-mode" => clipboard::clipboard_mode(),
        "wallpaper" => {
            let sub = rest.first().map(String::as_str).unwrap_or("list");
            match sub {
                "apply" => {
                    let path = rest.get(1).ok_or("Expected wallpaper path")?;
                    wallpaper::apply(&PathBuf::from(path))
                }
                "random" => wallpaper::apply_random(),
                "list" => {
                    for item in wallpaper::discover() {
                        println!("{}\t{}\t{}", item.category, item.stem, item.path.display());
                    }
                    Ok(())
                }
                _ => Err(error(format!("Unknown wallpaper subcommand: {sub}"))),
            }
        }
        "align" => {
            let current = text(&state().join("current_wallpaper"));
            if current.is_empty() {
                wallpaper::apply_random()
            } else {
                wallpaper_align::generate_alignment_crops(&PathBuf::from(current))
            }
        }
        "theme" => {
            let current = text(&state().join("current_wallpaper"));
            if current.is_empty() {
                wallpaper::apply_random()
            } else {
                theme::apply_theme(&PathBuf::from(current))
            }
        }
        "help" | "--help" | "-h" => {
            println!("Zenith Native Geometry & Theme Engine\n");
            println!("Usage: zenith-native <subcommand> [args]\n");
            println!("Subcommands:");
            println!("  wallpaper apply <path>  Apply wallpaper with grow transition, theme & 1:1 crops");
            println!("  wallpaper random        Select and apply a random wallpaper");
            println!("  wallpaper list          List all discovered wallpapers and categories");
            println!("  align                   Regenerate 1:1 pixel crops for current monitor");
            println!("  theme                   Regenerate theme palette from current wallpaper");
            Ok(())
        }
        _ => Err(error(format!("Unknown command: {cmd}"))),
    }
}
