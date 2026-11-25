use crate::config::*;
use image::{imageops::FilterType, DynamicImage, GenericImageView};
use serde_json::Value;
use std::{fs, path::Path};

pub struct MonitorGeometry {
    pub width: u32,
    pub height: u32,
}

pub fn active_monitor() -> MonitorGeometry {
    let mut geom = MonitorGeometry {
        width: 1920,
        height: 1080,
    };

    if let Ok(o) = run("hyprctl", &["monitors", "-j"]) {
        if let Ok(Value::Array(a)) = serde_json::from_slice(&o.stdout) {
            if let Some(m) = a
                .iter()
                .find(|m| m["focused"].as_bool() == Some(true))
                .or_else(|| a.first())
            {
                let w = m["width"].as_u64().unwrap_or(1920) as u32;
                let h = m["height"].as_u64().unwrap_or(1080) as u32;

                geom = MonitorGeometry {
                    width: w,
                    height: h,
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

    // Rofi's window border (2px on every side) insets the content box, so the
    // banner element is 480x(win_h-4). Cropping exactly that size keeps the
    // background-image 1:1 — if the crop were the full window height, rofi's
    // "height" sizing would rescale it (~1% shrink) and shift it ~2px, breaking
    // the seam against the desktop.
    let pane_w = pane_w.min(screen.width()).max(1);
    let launcher_h = win_h.saturating_sub(4).min(screen.height()).max(1);
    // The banner background starts inside the window's 2px border (padding is 0).
    let launcher_crop_x = (win_x + 2 + delta_x).min(screen.width().saturating_sub(pane_w));
    let launcher_crop_y = (win_y + 2 + delta_y).min(screen.height().saturating_sub(launcher_h));

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

    // ---------------------------------------------------------------------
    // 4. Clipboard wallpaper strips (rofi clipboard.rasi geometry)
    //    Window: 360px at north-east (x-offset -12px, y-offset 36px, 2px
    //    border, 0.5em mainbox padding, 10px em). The 50x38 frame gets a
    //    crisp 1:1 slice like the launcher banner; the 346x38 wallbox gets
    //    a matching blurred slice instead of a squeezed full crop.
    // ---------------------------------------------------------------------
    let strip_y = 43u32;
    let frame_w = 50u32;
    let strip_h = 38u32;
    let box_w = 346u32;
    let strip_sx = ((mon.width.saturating_sub(365)) + delta_x)
        .min(screen.width().saturating_sub(frame_w));
    let strip_sy = (strip_y + delta_y).min(screen.height().saturating_sub(strip_h));

    let clip_frame = screen
        .crop_imm(strip_sx, strip_sy, frame_w, strip_h);
    save_atomic(&clip_frame, &cache_dir.join("wall.clipboard.frame.png"))?;

    let clip_blur = screen
        .crop_imm(strip_sx, strip_sy, box_w, strip_h)
        .blur(10.0);
    save_atomic(&DynamicImage::ImageRgba8(clip_blur.to_rgba8()),
        &cache_dir.join("wall.clipboard.blur.png"))?;

    // 5. Lock screen background: the full monitor, blurred and dimmed.
    //    Hyprlock needs a real image file — pointing it at a state text file
    //    renders as a black screen.
    let lock_bg = screen
        .crop_imm(0, 0, mon.width.min(screen.width()), mon.height.min(screen.height()))
        .blur(14.0);
    let mut lock_tinted = lock_bg.to_rgba8();
    for p in lock_tinted.pixels_mut() {
        p[0] = (p[0] as f32 * 0.62) as u8;
        p[1] = (p[1] as f32 * 0.62) as u8;
        p[2] = (p[2] as f32 * 0.66) as u8;
    }
    let lock_image = DynamicImage::ImageRgba8(lock_tinted);
    save_atomic(&lock_image, &cache_dir.join("wall.lock.png"))?;

    // SDDM greeter runs as its own user and cannot read $HOME, so mirror the
    // exact same processed background and avatar into a world-readable path.
    let shared_dir = Path::new("/var/lib/zenith");
    if shared_dir.is_dir() {
        let _ = save_atomic(&lock_image, &shared_dir.join("lock-bg.png"));
    }

    let avatar_path = cache_dir.join("avatar.png");
    generate_avatar(&avatar_path, &[])?;
    if shared_dir.is_dir() {
        if let Ok(bytes) = fs::read(&avatar_path) {
            let _ = atomic(&shared_dir.join("avatar.png"), bytes);
        }
    }
    generate_power_icon(&cache_dir.join("power.png"))?;

    Ok(())
}

/// Draws the Zenith avatar: a two-tone gradient ring with a soft outer glow,
/// a dark glass disc and a geometric "Z" monogram. Pure raster (no fonts),
/// so it renders identically everywhere.
pub fn generate_avatar(path: &Path, _palette: &[&str]) -> Result {
    const S: u32 = 256;
    let cx = (S / 2) as f32;
    let cy = (S / 2) as f32;
    let r_ring = 112.0f32;
    let r_ring_in = 100.0f32;

    let mut img = image::RgbaImage::new(S, S);
    for y in 0..S {
        for x in 0..S {
            let dx = x as f32 - cx;
            let dy = y as f32 - cy;
            let dist = (dx * dx + dy * dy).sqrt();
            // angle 0..2pi for the ring gradient (accent -> cyan -> accent)
            let mut a = dx.atan2(dy) / std::f32::consts::TAU;
            if a < 0.0 { a += 1.0; }
            let t = if a < 0.5 { a * 2.0 } else { (1.0 - a) * 2.0 };
            // Accent #59B9E8 -> Cyan #7FD6E8
            let r = 89.0 + (127.0 - 89.0) * t;
            let g = 185.0 + (214.0 - 185.0) * t;
            let b = 232.0 + (232.0 - 232.0) * t;

            let px = img.get_pixel_mut(x, y);
            if dist <= r_ring_in {
                // Dark glass disc, slightly transparent towards the rim
                let shade = 14.0 + 10.0 * (dist / r_ring_in);
                *px = image::Rgba([shade as u8, (shade + 4.0) as u8,
                    (shade + 12.0) as u8, 235]);
            } else if dist <= r_ring + 10.0 {
                // Soft outer glow fading out
                let glow = (1.0 - (dist - r_ring) / 10.0).clamp(0.0, 1.0) * 70.0;
                *px = image::Rgba([r as u8, g as u8, b as u8, glow as u8]);
            }
            if dist > r_ring_in && dist <= r_ring {
                *px = image::Rgba([r as u8, g as u8, b as u8, 255]);
            }
        }
    }

    // Geometric "Z": two bars joined by a diagonal band, shaded
    // near-white -> accent left to right.
    let z_left = 84.0f32;
    let z_right = 172.0f32;
    let bar_top = 84.0f32;
    let bar_bot = 160.0f32;
    let bar_h = 15.0f32;
    for y in 0..S {
        for x in 0..S {
            let fx = x as f32;
            let fy = y as f32;
            let t = ((fx - z_left) / (z_right - z_left)).clamp(0.0, 1.0);
            // White -> accent diagonal shading
            let r = 235.0 + (89.0 - 235.0) * t * 0.75;
            let g = 242.0 + (185.0 - 242.0) * t * 0.75;
            let b = 250.0 + (232.0 - 250.0) * t * 0.75;

            let in_top_bar = fy >= bar_top && fy < bar_top + bar_h
                && fx >= z_left && fx < z_right;
            let in_bot_bar = fy >= bar_bot - bar_h && fy < bar_bot
                && fx >= z_left && fx < z_right;
            // Diagonal: connects the top bar's right end to the bottom bar's
            // left end, sweeping right -> left as y increases.
            let progress = ((fy - bar_top - bar_h) / (bar_bot - bar_top - 2.0 * bar_h))
                .clamp(0.0, 1.0);
            let span_mid = z_right - (z_right - z_left) * progress;
            let in_diag = fy >= bar_top + bar_h && fy < bar_bot - bar_h
                && (fx - span_mid).abs() <= 17.0;

            if in_top_bar || in_bot_bar || in_diag {
                let px = img.get_pixel_mut(x, y);
                *px = image::Rgba([r as u8, g as u8, b as u8, 255]);
            }
        }
    }

    save_atomic(&DynamicImage::ImageRgba8(img), path)
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
/// Draws the lock-screen power symbol (circle arc with a gap at the top +
/// vertical stem) as a raster PNG. Glyph-based icons kept failing to render
/// in hyprlock's font stack, so the button is now pure pixels: whatever the
/// system fonts do, this always shows.
pub fn generate_power_icon(path: &Path) -> Result {
    const S: u32 = 64;
    let cx = 32.0f32;
    let cy = 36.0f32;
    let r = 18.0f32;
    let half_thick = 2.5f32;
    // Gap half-angle at the top of the circle (the stem passes through it)
    let gap = 0.9f32; // radians around -90 degrees

    let mut img = image::RgbaImage::new(S, S);
    for y in 0..S {
        for x in 0..S {
            let fx = x as f32 + 0.5;
            let fy = y as f32 + 0.5;
            let dx = fx - cx;
            let dy = fy - cy;
            let dist = (dx * dx + dy * dy).sqrt();

            let mut on = false;
            // Stem: vertical bar from above the circle top down to centre
            if fx >= cx - 2.5 && fx <= cx + 2.5 && fy >= 6.0 && fy <= cy + 2.0 {
                on = true;
            }
            // Ring: only outside the top gap
            if (dist - r).abs() <= half_thick {
                let ang = dy.atan2(dx); // -pi..pi, top = -pi/2
                if ang > -std::f32::consts::FRAC_PI_2 - gap
                    && ang < -std::f32::consts::FRAC_PI_2 + gap
                {
                    // Inside the gap: only the stem shows
                } else {
                    on = true;
                }
            }

            if on {
                // Soft antialiasing via distance to the stem edges
                let px = img.get_pixel_mut(x, y);
                // Near-white to match the lock screen text
                *px = image::Rgba([220, 230, 245, 255]);
            }
        }
    }

    save_atomic(&DynamicImage::ImageRgba8(img), path)
}
