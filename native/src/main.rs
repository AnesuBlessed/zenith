mod clipboard;
mod config;
mod notify;
mod palette;
mod theme;
mod thumbs;
mod wallpaper;
mod wallpaper_align;

use config::*;
use std::path::PathBuf;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(e) = dispatch(&args) {
        eprintln!("Zenith-Native Error: {e}");
        std::process::exit(1);
    }
}

fn flag(args: &[String], name: &str) -> Option<String> {
    let index = args.iter().position(|a| a == name)?;
    args.get(index + 1).cloned()
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
                "list" => {
                    for item in wallpaper::discover() {
                        println!("{}", item.path.display());
                    }
                    Ok(())
                }
                "list-long" => {
                    for item in wallpaper::discover() {
                        println!("{}\t{}\t{}", item.category, item.stem, item.path.display());
                    }
                    Ok(())
                }
                "current" => {
                    println!("{}", wallpaper::current());
                    Ok(())
                }
                "set" | "apply" => {
                    let path = rest.get(1).ok_or("Expected wallpaper path")?;
                    let transition = flag(rest, "--transition").unwrap_or_else(|| "fade".into());
                    let duration = flag(rest, "--duration").unwrap_or_else(|| "1.0".into());
                    let monitor = flag(rest, "--monitor").unwrap_or_default();
                    let reduced = rest.iter().any(|a| a == "--reduced-motion");
                    wallpaper::set(&PathBuf::from(path), &transition, &duration, &monitor, reduced)
                }
                "random" => wallpaper::apply_random(),
                "probe" => wallpaper::probe(),
                "ensure" => wallpaper::ensure(),
                "thumbs" => {
                    let force = rest.iter().any(|a| a == "--force");
                    wallpaper::thumbnails(force)
                }
                _ => Err(error(format!("Unknown wallpaper subcommand: {sub}"))),
            }
        }
        "notify" => {
            let sub = rest.first().map(String::as_str).unwrap_or("snapshot");
            match sub {
                "daemon" => notify::daemon(),
                "snapshot" => notify::snapshot(),
                _ => Err(error(format!("Unknown notify subcommand: {sub}"))),
            }
        }
        "align" => {
            let current = wallpaper::current();
            if current.is_empty() {
                wallpaper::apply_random()
            } else {
                let visual = text(&state().join("current_wallpaper_image"));
                let target = if visual.is_empty() {
                    PathBuf::from(current)
                } else {
                    PathBuf::from(visual)
                };
                wallpaper_align::generate_alignment_crops(&target)
            }
        }
        "theme" => {
            let sub = rest.first().map(String::as_str).unwrap_or("refresh");
            match sub {
                "refresh" => theme::refresh(),
                "color" => {
                    let color = rest.get(1).ok_or("Expected a #rrggbb colour")?;
                    theme::from_color(color)
                }
                _ => Err(error(format!("Unknown theme subcommand: {sub}"))),
            }
        }
        "help" | "--help" | "-h" => {
            println!("Zenith Native Engine\n");
            println!("Usage: zenith-native <subcommand> [args]\n");
            println!("Subcommands:");
            println!("  wallpaper list                  List discovered wallpapers (absolute paths)");
            println!("  wallpaper list-long             List wallpapers as category<TAB>name<TAB>path");
            println!("  wallpaper set <path> [--transition T] [--duration S] [--monitor M] [--reduced-motion]");
            println!("  wallpaper random                Apply a random wallpaper");
            println!("  wallpaper ensure                Re-apply the last wallpaper (or pick one)");
            println!("  wallpaper probe                 Report wallpaper daemon availability");
            println!("  wallpaper current               Print the active wallpaper path");
            println!("  wallpaper thumbs [--force]      Generate picker thumbnails");
            println!("  theme [refresh|color <#hex>]    Regenerate or override the palette");
            println!("  align                           Regenerate launcher/clipboard crops");
            println!("  notify daemon                   Run the notification presentation engine");
            println!("  notify snapshot                 Print the current notification snapshot");
            Ok(())
        }
        _ => Err(error(format!("Unknown command: {cmd}"))),
    }
}