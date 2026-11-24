use crate::config::*;
use image::{imageops::FilterType, ImageEncoder};
use std::{fs::File, io::BufWriter, path::{Path, PathBuf}, process::Command};

/// Thumbnail service for the wallpaper picker. Images are decoded with the same
/// `image` crate the aligner uses, so no ImageMagick dependency is required.
pub fn thumb_dir() -> PathBuf {
    cache().join("thumbs")
}

fn thumbnail(source: &Path, target: &Path) -> Result {
    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let image = image::open(source)?;
    let scaled = if image.height() > 500 {
        let ratio = 500.0 / image.height() as f64;
        let width = (image.width() as f64 * ratio).round().max(1.0) as u32;
        image.resize(width, 500, FilterType::Triangle)
    } else {
        image
    };
    let rgb = scaled.to_rgb8();
    let file = BufWriter::new(File::create(target)?);
    image::codecs::png::PngEncoder::new(file).write_image(
        rgb.as_raw(),
        rgb.width(),
        rgb.height(),
        image::ExtendedColorType::Rgb8,
    )?;
    Ok(())
}

fn video_still(source: &Path, target: &Path) -> bool {
    if !exists("ffmpeg") {
        return false;
    }
    let status = Command::new("ffmpeg")
        .args(["-y", "-loglevel", "error", "-ss", "2", "-i"])
        .arg(source)
        .args(["-vframes", "1", "-vf", "scale='min(2560,iw)':-2"])
        .arg(target)
        .status();
    matches!(status, Ok(s) if s.success()) && target.is_file()
}

pub fn picker_dir() -> PathBuf {
    cache().join("picker")
}

/// Flat symlink index consumed by the QML picker, whose FolderListModel cannot
/// recurse into the bundled wallpaper subdirectories. Names are de-duplicated
/// because two categories may contain a file with the same basename.
fn unique_names(items: &[crate::wallpaper::WallpaperItem]) -> Vec<String> {
    let mut used = std::collections::HashSet::new();
    // Thumbnail files are named after the stem, so two different extensions
    // with the same stem would overwrite each other (foo.jpg vs foo.mp4).
    let mut stems = std::collections::HashSet::new();
    let mut names = Vec::with_capacity(items.len());
    for item in items {
        let base = item
            .path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "wallpaper".into());
        let stem = Path::new(&base)
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| "wallpaper".into());
        let ext = Path::new(&base)
            .extension()
            .map(|e| format!(".{}", e.to_string_lossy()))
            .unwrap_or_default();
        let mut candidate = base.clone();
        let mut suffix = 2usize;
        loop {
            let candidate_stem = Path::new(&candidate)
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            if !used.contains(&candidate) && !stems.contains(&candidate_stem) {
                used.insert(candidate.clone());
                stems.insert(candidate_stem);
                break;
            }
            candidate = format!("{stem}-{suffix}{ext}");
            suffix += 1;
        }
        names.push(candidate);
    }
    names
}

fn refresh_picker_index(items: &[crate::wallpaper::WallpaperItem], names: &[String]) -> Result {
    let dir = picker_dir();
    std::fs::create_dir_all(&dir)?;
    let mut wanted = std::collections::HashSet::new();
    for (item, name) in items.iter().zip(names.iter()) {
        wanted.insert(name.clone());
        let link = dir.join(name);
        let correct = std::fs::read_link(&link)
            .map(|target| target == item.path)
            .unwrap_or(false);
        if correct {
            continue;
        }
        let _ = std::fs::remove_file(&link);
        std::os::unix::fs::symlink(&item.path, &link)?;
    }
    if let Ok(entries) = std::fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            // `.current` is picker metadata, not an index entry.
            if name == ".current" {
                continue;
            }
            if !wanted.contains(&name) {
                let _ = std::fs::remove_file(entry.path());
            }
        }
    }
    Ok(())
}

/// Rebuilds the flat symlink index without touching thumbnails.
pub fn refresh_index() -> Result {
    let items = crate::wallpaper::discover();
    let names = unique_names(&items);
    refresh_picker_index(&items, &names)
}

/// The flat symlink that currently points at `path`, if the picker index has one.
pub fn link_for(path: &Path) -> Option<PathBuf> {
    let canonical = path.canonicalize().ok()?;
    let entries = std::fs::read_dir(picker_dir()).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        if let Ok(target) = entry.path().canonicalize() {
            if target == canonical {
                return Some(entry.path());
            }
        }
    }
    None
}

pub fn generate(force: bool) -> Result {
    let dir = thumb_dir();
    std::fs::create_dir_all(&dir)?;
    let mut generated = 0usize;
    let items = crate::wallpaper::discover();
    let names = unique_names(&items);
    refresh_picker_index(&items, &names)?;
    for (item, name) in items.iter().zip(names.iter()) {
        if crate::wallpaper::is_video(&item.path) {
            let stem = Path::new(name)
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            let still = dir.join(format!("{stem}.hq.jpg"));
            let card = dir.join(format!("{stem}.jpg"));
            if force || !still.is_file() {
                if !video_still(&item.path, &still) {
                    continue;
                }
            }
            if force || !card.is_file() {
                if thumbnail(&still, &card).is_ok() {
                    generated += 1;
                }
            }
            continue;
        }
        let target = dir.join(name);
        if !force && target.is_file() {
            continue;
        }
        match thumbnail(&item.path, &target) {
            Ok(()) => {
                generated += 1;
                println!("THUMB {name}");
            }
            Err(err) => eprintln!("Zenith: thumbnail failed for {name}: {err}"),
        }
    }
    println!("THUMBS={generated}");
    Ok(())
}