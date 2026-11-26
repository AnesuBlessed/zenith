//! Fastfetch brand banner.
//!
//! The lock screen / SDDM / island can use real fonts; a terminal renders
//! one font for all text, so the two brand elements (the ZENITH heading and
//! the Gojo quote) are rasterized in Zenith Display and shown by fastfetch
//! through foot's sixel image support. Drawn here in Rust with `fontdue`
//! so the result is deterministic — no ImageMagick font lookup to fail.

use crate::config::{atomic, error, root};
use fontdue::{Font, FontSettings};
use image::{DynamicImage, Rgba, RgbaImage};
use std::path::{Path, PathBuf};

struct Line {
    text: &'static str,
    size: f32,
    color: [u8; 3],
    gap_above: u32,
}

const LINES: &[Line] = &[
    Line { text: "ZENITH", size: 92.0, color: [228, 235, 245], gap_above: 0 },
    Line { text: "Hyprland Workstation", size: 34.0, color: [154, 167, 184], gap_above: 18 },
    Line { text: "Throughout Heaven and Earth,", size: 36.0, color: [127, 214, 232], gap_above: 44 },
    Line { text: "I Alone Am the Honored One", size: 36.0, color: [127, 214, 232], gap_above: 8 },
];

fn font_path() -> PathBuf {
    root().join("fonts").join("ZenithDisplay-Bold.ttf")
}

/// Rasterize the banner to `$XDG_CACHE_HOME/zenith/zenith-fastfetch.png`.
/// Missing font file or unreadable text simply skips generation — fastfetch
/// then shows no banner instead of a broken one.
pub fn generate(target: &Path) -> Result {
    let data = match std::fs::read(font_path()) {
        Ok(data) => data,
        Err(_) => return Ok(()),
    };
    let font = Font::from_bytes(
        data,
        FontSettings {
            collection_index: 0,
            scale: 120.0,
            ..Default::default()
        },
    )
    .map_err(|e| error(format!("Zenith Display font unreadable: {e}")))?;

    const PAD: u32 = 10;
    // Measure first: widest line and total height with the gaps.
    let mut width = 0u32;
    let mut height = PAD;
    let mut layouts = Vec::new();
    for line in LINES {
        let mut pen = 0.0f32;
        let mut glyphs = Vec::new();
        for ch in line.text.chars() {
            let (metrics, _bitmap) = font.rasterize(ch, line.size);
            glyphs.push((ch, metrics.advance_width));
            pen += metrics.advance_width;
        }
        let line_width = pen.ceil() as u32;
        width = width.max(line_width);
        height += line.gap_above + line.size.ceil() as u32;
        layouts.push(glyphs);
    }
    width += PAD * 2;
    height += PAD;

    let mut img = RgbaImage::new(width, height);
    let mut y = PAD as f32;
    for (line, glyphs) in LINES.iter().zip(layouts.iter()) {
        y += line.gap_above as f32;
        let mut pen = PAD as f32;
        for (ch, advance) in glyphs {
            let (metrics, bitmap) = font.rasterize(*ch, line.size);
            let xmin = pen as i32 + metrics.xmin;
            let ymin = y as i32 + metrics.ymin;
            for (index, coverage) in bitmap.iter().enumerate() {
                if *coverage == 0 {
                    continue;
                }
                let gx = xmin + (index % metrics.width as usize) as i32;
                let gy = ymin + (index / metrics.width as usize) as i32;
                if gx < 0 || gy < 0
                    || gx >= img.width() as i32 || gy >= img.height() as i32
                {
                    continue;
                }
                let alpha = *coverage as f32 / 255.0;
                let pixel = img.get_pixel_mut(gx as u32, gy as u32);
                // Straight-alpha blend over what is already there.
                let base = pixel.0;
                let out: [u8; 3] = [
                    (line.color[0] as f32 * alpha + base[0] as f32 * (1.0 - alpha)) as u8,
                    (line.color[1] as f32 * alpha + base[1] as f32 * (1.0 - alpha)) as u8,
                    (line.color[2] as f32 * alpha + base[2] as f32 * (1.0 - alpha)) as u8,
                ];
                let out_alpha = (255.0f32 * alpha + base[3] as f32 * (1.0 - alpha)) as u8;
                *pixel = Rgba([out[0], out[1], out[2], out_alpha]);
            }
            pen += advance;
        }
        y += line.size;
    }

    atomic(&DynamicImage::ImageRgba8(img), target)?;
    Ok(())
}
