use crate::config::*;
use image::{imageops::FilterType, DynamicImage, GenericImageView, Rgb, RgbImage};
use serde_json::Value;
use std::{fs, path::Path};

pub struct MonitorGeometry {
    pub width: u32,
    pub height: u32,
    pub scale: f64,
    pub x: i32,
    pub y: i32,
}

pub fn active_monitor() -> MonitorGeometry {
    let mut geom = MonitorGeometry {
        width: 1920,
        height: 1080,
        scale: 1.0,
        x: 0,
        y: 0,
    };

    if let Ok(o) = run("hyprctl", &["monitors", "-j"]) {
        if let Ok(Value::Array(a)) = serde_json::from_slice(&o.stdout) {
            if let Some(m) = a
                .iter()
                .find(|m| m["focused"].as_bool() == Some(true))
                .or_else(|| a.first())
            {
                let scale = m["scale"].as_f64().unwrap_or(1.0).max(0.5);
                let w = m["width"].as_u64().unwrap_or(1920) as u32;
                let h = m["height"].as_u64().unwrap_or(1080) as u32;
                let x = m["x"].as_i64().unwrap_or(0) as i32;
                let y = m["y"].as_i64().unwrap_or(0) as i32;

                geom = MonitorGeometry {
                    width: w,
                    height: h,
                    scale,
                    x,
                    y,
                };
            }
        }
    }
    geom
}

/// Computes the exact 1:1 pixel crops for the centered launcher and top-right clipboard.
pub fn generate_alignment_crops(wall_path: &Path) -> Result {
    let mon = active_monitor();
    let cache_dir = cache();
    fs::create_dir_all(&cache_dir)?;

    let img = image::open(wall_path)?;
    let (img_w, img_h) = img.dimensions();

    if img_w == 0 || img_h == 0 {
        return Err(error("Invalid wallpaper dimensions"));
    }

    // 1. Calculate aspect-fill scaling factor identical to swww/hyprpaper
    let scale_x = mon.width as f64 / img_w as f64;
    let scale_y = mon.height as f64 / img_h as f64;
    let s = scale_x.max(scale_y);

    let scaled_w = (img_w as f64 * s).round() as u32;
    let scaled_h = (img_h as f64 * s).round() as u32;

    // Rescale source image to fill monitor viewport
    let screen = img.resize_to_fill(scaled_w, scaled_h, FilterType::Lanczos3);

    // Center offset inside the aspect-filled canvas
    let delta_x = (scaled_w.saturating_sub(mon.width)) / 2;
    let delta_y = (scaled_h.saturating_sub(mon.height)) / 2;

    // -------------------------------------------------------------------------
    // 2. Dual-Pane Launcher Crop (Window: 960x420 centered on screen)
    // -------------------------------------------------------------------------
    let win_w = 960u32;
    let win_h = 420u32;
    let pane_w = 480u32; // Left half of dual-pane window

    let win_x = (mon.width.saturating_sub(win_w)) / 2;
    let win_y = (mon.height.saturating_sub(win_h)) / 2;

    let pane_w = pane_w.min(screen.width()).max(1);
    let launcher_h = win_h.min(screen.height()).max(1);
    let launcher_crop_x = (win_x + delta_x).min(screen.width().saturating_sub(pane_w));
    let launcher_crop_y = (win_y + delta_y).min(screen.height().saturating_sub(launcher_h));

    // A. 1:1 Exact crisp wallpaper slice for left banner
    let launcher_slice = screen.crop_imm(launcher_crop_x, launcher_crop_y, pane_w, launcher_h);
    let launcher_slice_path = cache_dir.join("wall.launcher.png");
    save_atomic(&launcher_slice, &launcher_slice_path)?;

    // B. Frosted Glass Vertical Rail (56px width with edge-padded Gaussian blur)
    let rail_w = 56u32.min(screen.width()).max(1);
    let rail_slice = screen
        .crop_imm(launcher_crop_x, launcher_crop_y, rail_w, launcher_h)
        .blur(10.0);
    
    // Subtle dark tint for glass depth
    let mut rail_tinted = rail_slice.to_rgba8();
    for p in rail_tinted.pixels_mut() {
        p[0] = ((p[0] as f32 * 0.75) + 12.0) as u8;
        p[1] = ((p[1] as f32 * 0.75) + 16.0) as u8;
        p[2] = ((p[2] as f32 * 0.75) + 24.0) as u8;
    }
    let launcher_blur_path = cache_dir.join("wall.launcher.blur.png");
    save_atomic(&DynamicImage::ImageRgba8(rail_tinted), &launcher_blur_path)?;

    // -------------------------------------------------------------------------
    // 3. Anchored Clipboard Crop (Window: 360x430, top-right anchor)
    // -------------------------------------------------------------------------
    let clip_w = 360u32;
    let clip_h = 430u32;
    let clip_x = mon.width.saturating_sub(clip_w + 12);
    let clip_y = 44u32; // Underneath the Dynamic Island

    let clip_w = clip_w.min(screen.width()).max(1);
    let clip_h = clip_h.min(screen.height()).max(1);
    let clip_crop_x = (clip_x + delta_x).min(screen.width().saturating_sub(clip_w));
    let clip_crop_y = (clip_y + delta_y).min(screen.height().saturating_sub(clip_h));

    let clip_slice = screen
        .crop_imm(clip_crop_x, clip_crop_y, clip_w, clip_h)
        .blur(12.0);
    let clip_slice_path = cache_dir.join("wall.clipboard.png");
    save_atomic(&clip_slice, &clip_slice_path)?;

    Ok(())
}

/// Writes an image through a temp file + rename so a rofi window opened
/// mid-transaction can never read a half-written PNG.
fn save_atomic(image: &DynamicImage, path: &Path) -> Result {
    // Temp name keeps the .png suffix: `image::save` picks the encoder from it.
    let temp = path.with_file_name(format!(
        "{}.tmp-{}.png",
        path.file_stem().and_then(|s| s.to_str()).unwrap_or("crop"),
        std::process::id()
    ));
    let result = (|| {
        image.save(&temp)?;
        fs::rename(&temp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}