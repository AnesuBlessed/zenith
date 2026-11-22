use crate::{config::*, theme, wallpaper_align};
use std::{collections::HashSet, fs, path::{Path, PathBuf}};

#[derive(Clone, Debug)]
pub struct WallpaperItem {
    pub path: PathBuf,
    pub category: String,
    pub stem: String,
}

pub fn discover() -> Vec<WallpaperItem> {
    let roots = [
        root().join("wallpapers"),
        xdg("XDG_DATA_HOME", ".local/share").join("zenith/wallpapers"),
        home().join("Pictures/Wallpapers"),
        home().join("Documents/Wallpapers"),
    ];

    let mut seen = HashSet::new();
    let mut items = Vec::new();

    for root_dir in roots {
        if !root_dir.is_dir() {
            continue;
        }
        for p in walk(&root_dir) {
            let ext = p
                .extension()
                .map(|e| e.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            if !["png", "jpg", "jpeg", "webp"].contains(&ext.as_str()) {
                continue;
            }
            if let Ok(canon) = p.canonicalize() {
                if seen.insert(canon.clone()) {
                    let rel = p.strip_prefix(&root_dir).unwrap_or(&p);
                    let category = if rel.components().count() > 1 {
                        rel.components()
                            .next()
                            .unwrap()
                            .as_os_str()
                            .to_string_lossy()
                            .into_owned()
                    } else {
                        "General".into()
                    };
                    let stem = p
                        .file_stem()
                        .map(|s| s.to_string_lossy().into_owned())
                        .unwrap_or_else(|| "wallpaper".into());

                    items.push(WallpaperItem {
                        path: canon,
                        category,
                        stem,
                    });
                }
            }
        }
    }
    items
}

pub fn apply(path: &Path) -> Result {
    let wall = path.canonicalize()?;
    if !wall.is_file() {
        return Err(error("Specified wallpaper is not a file"));
    }

    // 1. Desktop Wallpaper Daemon Transition (swww / hyprpaper)
    let wall_str = wall.to_string_lossy();
    let mut applied = false;

    if exists("swww") {
        let _ = run("swww-daemon", &[]);
        let res = run(
            "swww",
            &[
                "img",
                &wall_str,
                "--transition-type",
                "grow",
                "--transition-duration",
                "1.0",
                "--transition-fps",
                "144",
            ],
        );
        if res.is_ok_and(|o| o.status.success()) {
            applied = true;
        }
    }

    if !applied && exists("hyprctl") {
        let _ = run("hyprctl", &["hyprpaper", "preload", &wall_str]);
        let _ = run("hyprctl", &["hyprpaper", "wallpaper", &format!(",{}", wall_str)]);
    }

    // 2. Pre-generate 1:1 Pixel-Perfect Crops for Launcher and Clipboard
    wallpaper_align::generate_alignment_crops(&wall)?;

    // 3. Extract & Apply Dynamic Palette
    theme::apply_theme(&wall)?;

    // 4. Save State
    atomic(
        &state().join("current_wallpaper"),
        format!("{}\n", wall.display()),
    )?;

    // 5. Notify Desktop Components
    let _ = run(
        "notify-send",
        &[
            "-a",
            "Zenith",
            "-i",
            &wall_str,
            "Wallpaper Applied",
            &wall.file_name().unwrap_or_default().to_string_lossy(),
        ],
    );

    Ok(())
}

pub fn apply_random() -> Result {
    let items = discover();
    if items.is_empty() {
        return Err(error("No wallpapers found"));
    }
    use std::time::SystemTime;
    let seed = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(42) as usize;
    let index = seed % items.len();
    apply(&items[index].path)
}
