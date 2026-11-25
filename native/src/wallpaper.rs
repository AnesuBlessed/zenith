use crate::{config::*, palette, thumbs, wallpaper_align};
use std::{collections::HashSet, fs, path::{Path, PathBuf}, process::{Command, Stdio}, thread, time::Duration};

#[derive(Clone, Debug)]
pub struct WallpaperItem {
    pub path: PathBuf,
    pub category: String,
    pub stem: String,
}

pub fn roots() -> Vec<PathBuf> {
    vec![
        root().join("wallpapers"),
        xdg("XDG_DATA_HOME", ".local/share").join("zenith/wallpapers"),
        home().join("Pictures/Wallpapers"),
        home().join("Pictures/wallpapers"),
        home().join("Pictures"),
    ]
}

pub fn discover() -> Vec<WallpaperItem> {
    let videos_supported = exists("mpvpaper");
    let mut seen = HashSet::new();
    let mut items = Vec::new();
    for root_dir in roots() {
        if !root_dir.is_dir() {
            continue;
        }
        for path in walk(&root_dir) {
            let ext = path
                .extension()
                .map(|e| e.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            if !["png", "jpg", "jpeg", "webp"].contains(&ext.as_str()) && !is_video(&path) {
                continue;
            }
            // Without mpvpaper a video can never be displayed, so keep it out of
            // the picker/library instead of offering an action that always fails.
            if is_video(&path) && !videos_supported {
                continue;
            }
            if let Ok(canonical) = path.canonicalize() {
                if !seen.insert(canonical.clone()) {
                    continue;
                }
                let relative = path.strip_prefix(&root_dir).unwrap_or(&path);
                let category = if relative.components().count() > 1 {
                    relative
                        .components()
                        .next()
                        .unwrap()
                        .as_os_str()
                        .to_string_lossy()
                        .into_owned()
                } else {
                    "General".into()
                };
                let stem = path
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_else(|| "wallpaper".into());
                items.push(WallpaperItem { path: canonical, category, stem });
            }
        }
    }
    items.sort_by(|a, b| a.path.cmp(&b.path));
    items
}

pub fn is_video(path: &Path) -> bool {
    matches!(
        path.extension()
            .map(|e| e.to_string_lossy().to_lowercase())
            .unwrap_or_default()
            .as_str(),
        "mp4" | "webm" | "mov" | "mkv" | "avi" | "m4v" | "gif" | "flv"
            | "wmv" | "mpeg" | "mpg" | "3gp"
    )
}

/// Accepts plain paths and file:// URLs (QML models hand both around).
fn url_to_path(path: &Path) -> PathBuf {
    let raw = path.to_string_lossy().to_string();
    let Some(rest) = raw.strip_prefix("file://") else {
        return path.to_path_buf();
    };
    let decoded = rest.split('?').next().unwrap_or(rest);
    let bytes = decoded.as_bytes();
    let mut out = String::with_capacity(decoded.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(value) = u8::from_str_radix(&decoded[i + 1..i + 3], 16) {
                out.push(value as char);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    PathBuf::from(out)
}

fn daemon_running() -> bool {
    run("swww", &["query"]).is_ok_and(|o| o.status.success())
}

fn ensure_daemon() -> Result {
    if daemon_running() {
        return Ok(());
    }
    if !exists("swww") {
        return Err(error("swww is not installed (pacman -S swww)"));
    }
    if exists("swww-daemon") {
        let _ = Command::new("swww-daemon")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
    for _ in 0..30 {
        thread::sleep(Duration::from_millis(100));
        if daemon_running() {
            return Ok(());
        }
    }
    Err(error("swww-daemon did not become ready"))
}

fn transition_flags(kind: &str, duration: &str, reduced: bool) -> Vec<String> {
    let mut flags: Vec<String> = Vec::new();
    if reduced {
        flags.push("--transition-type".into());
        flags.push("none".into());
        return flags;
    }
    let (name, angle) = match kind {
        "fade" => ("fade", None),
        "slide" => ("wipe", Some("90")),
        "wipe" => ("wipe", Some("45")),
        "wave" => ("wave", Some("0")),
        "expand" => ("grow", None),
        "contract" => ("outer", None),
        "spotlight" => ("center", None),
        "random" => ("random", None),
        _ => ("grow", None),
    };
    flags.push("--transition-type".into());
    flags.push(name.into());
    if let Some(angle) = angle {
        flags.push("--transition-angle".into());
        flags.push(angle.into());
    }
    flags.push("--transition-duration".into());
    flags.push(duration.into());
    flags.push("--transition-fps".into());
    flags.push("60".into());
    flags
}

fn start_video(path: &Path, monitor: &str) -> Result {
    if !exists("mpvpaper") {
        return Err(error("mpvpaper is required for video wallpapers (AUR: mpvpaper)"));
    }
    let _ = run("pkill", &["-x", "mpvpaper"]);
    Command::new("mpvpaper")
        .arg("-f")
        .arg("-o")
        .arg("no-audio loop")
        .arg(monitor)
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    thread::sleep(Duration::from_millis(250));
    Ok(())
}

/// Static frame used by hyprlock and the launcher crops. Videos cannot be
/// decoded by the image crate, so ffmpeg writes one still into the state dir.
fn still_for(path: &Path) -> Option<PathBuf> {
    if !is_video(path) {
        return Some(path.to_path_buf());
    }
    if !exists("ffmpeg") {
        return None;
    }
    let still = state().join("video_still.png");
    let ok = Command::new("ffmpeg")
        .args(["-y", "-loglevel", "error", "-ss", "1", "-i"])
        .arg(path)
        .args(["-vframes", "1"])
        .arg(&still)
        .status()
        .map(|status| status.success())
        .unwrap_or(false);
    if ok && still.is_file() {
        Some(still)
    } else {
        None
    }
}

/// Applies a wallpaper and refreshes every derived artefact (palette, Hyprland
/// colours, terminal theme, rofi tokens, launcher crops, state file).
pub fn set(path: &Path, transition: &str, duration: &str, monitor: &str, reduced: bool) -> Result {
    let wall = url_to_path(path).canonicalize()?;
    if !wall.is_file() {
        return Err(error(format!("Wallpaper not found: {}", path.display())));
    }
    let wall_str = wall.to_string_lossy().to_string();

    if is_video(&wall) {
        start_video(&wall, if monitor.is_empty() { "*" } else { monitor })?;
    } else {
        let _ = run("pkill", &["-x", "mpvpaper"]);
        ensure_daemon()?;
        let mut args: Vec<String> = vec!["img".into(), wall_str.clone()];
        args.extend(transition_flags(transition, duration, reduced));
        if !monitor.is_empty() && monitor != "all" {
            args.push("--outputs".into());
            args.push(monitor.to_string());
        }
        let borrowed: Vec<&str> = args.iter().map(String::as_str).collect();
        let output = run("swww", &borrowed)?;
        if !output.status.success() {
            return Err(error(format!(
                "swww rejected the wallpaper: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            )));
        }
    }

    let display = still_for(&wall);
    let visual = display.as_deref().unwrap_or(&wall);
    let _ = wallpaper_align::generate_alignment_crops(visual);
    atomic(
        &state().join("current_wallpaper_image"),
        format!("{}\n", visual.to_string_lossy()),
    )?;
    let palette = palette::regenerate_from(&wall)?;
    atomic(&state().join("current_wallpaper"), format!("{wall_str}\n"))?;
    // Picker cards point at flat symlinks, so record the symlink path (not the
    // canonical target) for the active-card highlight. The sidecar is metadata
    // and is skipped by index pruning.
    let _ = thumbs::refresh_index();
    let picker_current = thumbs::link_for(&wall).unwrap_or_else(|| wall.clone());
    let _ = atomic(
        &cache().join("picker/.current"),
        format!("{}\n", picker_current.to_string_lossy()),
    );
    let seed = palette["seed"].as_str().unwrap_or("#a899e6").to_string();
    atomic(&cache().join("current_seed"), format!("{seed}\n"))?;

    if exists("hyprctl") {
        let _ = run("hyprctl", &["reload"]);
    }

    if exists("notify-send") {
        let name = wall
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let _ = run("notify-send", &[
            "-a",
            "Zenith",
            "-i",
            &wall_str,
            "Wallpaper applied",
            &name,
        ]);
    }

    println!("STATE=ready");
    println!("COMMITTED=true");
    println!("PALETTE=updated");
    println!("WALLPAPER={wall_str}");
    Ok(())
}

pub fn apply_random() -> Result {
    let all = discover();
    if all.is_empty() {
        return Err(error("No wallpapers found in ~/Pictures/Wallpapers or Zenith's wallpapers folder"));
    }
    // A fresh install may not have mpvpaper; never pick a video that cannot
    // be shown in that case.
    let items: Vec<WallpaperItem> = if exists("mpvpaper") {
        all
    } else {
        all.into_iter().filter(|item| !is_video(&item.path)).collect()
    };
    if items.is_empty() {
        return Err(error("No image wallpapers found (install mpvpaper for video support)"));
    }
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0) as usize;
    set(&items[seed % items.len()].path, "fade", "1.0", "", false)
}


/// Health probe used by the shell at boot and by the retry button.
pub fn probe() -> Result {
    if !exists("swww") {
        println!("STATE=missing");
        return Ok(());
    }
    if !daemon_running() {
        println!("STATE=starting");
        let _ = ensure_daemon();
    }
    if daemon_running() {
        println!("STATE=ready");
    } else {
        println!("STATE=starting");
    }
    let current = current();
    if !current.is_empty() {
        println!("CURRENT={current}");
    }
    Ok(())
}

/// Re-applies the last wallpaper (or picks one on first boot) so every
/// derived artefact exists after login.
pub fn ensure() -> Result {
    let current = current();
    let applied = if !current.is_empty() && std::path::Path::new(&current).is_file() {
        set(std::path::Path::new(&current), "fade", "1.0", "", false)
    } else {
        apply_random()
    };
    // Warm the picker cache (flat symlink index + thumbnails) during login so
    // the standalone picker has content the first time it opens.
    let _ = crate::thumbs::generate(false);
    applied
}

pub fn current() -> String {
    text(&state().join("current_wallpaper"))
}

/// Regenerates thumbnails consumed by the picker (`thumbs.rs`).
pub fn thumbnails(force: bool) -> Result {
    crate::thumbs::generate(force)
}

pub fn ensure_dir(path: &Path) -> Result {
    fs::create_dir_all(path)?;
    Ok(())
}