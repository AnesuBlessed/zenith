use crate::config::*;
use image::{imageops::FilterType, DynamicImage, GenericImageView, Rgb};
use std::{collections::HashMap, fs, path::Path};

pub struct Palette {
    pub accent: String,
    pub accent_rgb: [u8; 3],
    pub bg: String,
    pub fg: String,
    pub surface: String,
    pub border: String,
    pub selection: String,
}

pub fn extract_palette(img_path: &Path) -> Result<Palette> {
    let img = image::open(img_path)?;
    let thumb = img.resize_exact(64, 64, FilterType::Triangle);
    let rgb = thumb.to_rgb8();

    let mut color_counts: HashMap<[u8; 3], u32> = HashMap::new();
    let mut total_r = 0u64;
    let mut total_g = 0u64;
    let mut total_b = 0u64;

    for p in rgb.pixels() {
        total_r += p[0] as u64;
        total_g += p[1] as u64;
        total_b += p[2] as u64;

        // Quantize colors into 16-step buckets
        let q = [p[0] / 16 * 16, p[1] / 16 * 16, p[2] / 16 * 16];
        *color_counts.entry(q).or_insert(0) += 1;
    }

    // Find the most vibrant color with sufficient saturation and luminosity
    let mut best_accent = [168, 153, 230]; // Default soft purple
    let mut best_score = 0.0f32;

    for (c, count) in color_counts {
        let r = c[0] as f32 / 255.0;
        let g = c[1] as f32 / 255.0;
        let b = c[2] as f32 / 255.0;

        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let delta = max - min;
        let sat = if max > 0.0 { delta / max } else { 0.0 };
        let lum = (max + min) / 2.0;

        // Prefer saturated, medium-bright colors
        if sat > 0.25 && lum > 0.25 && lum < 0.85 {
            let score = sat * (1.0 - (lum - 0.55).abs()) * (count as f32);
            if score > best_score {
                best_score = score;
                best_accent = c;
            }
        }
    }

    let accent_hex = format!("#{:02x}{:02x}{:02x}", best_accent[0], best_accent[1], best_accent[2]);
    let border_hex = format!("#{:02x}{:02x}{:02x}", 
        (best_accent[0] as f32 * 0.7) as u8, 
        (best_accent[1] as f32 * 0.7) as u8, 
        (best_accent[2] as f32 * 0.7) as u8
    );

    Ok(Palette {
        accent: accent_hex,
        accent_rgb: best_accent,
        bg: "#0d1017".into(),
        fg: "#f0f3f6".into(),
        surface: "#161b22".into(),
        border: border_hex,
        selection: "#21262d".into(),
    })
}

pub fn apply_theme(wall_path: &Path) -> Result {
    let p = extract_palette(wall_path)?;
    let theme_dir = home().join(".config/zenith/theme");
    fs::create_dir_all(&theme_dir)?;

    // 1. Generate Hyprland Lua Colors Module
    let hypr_colors = format!(
        "-- Zenith Generated Palette Module (Lua)\n\
        return {{\n\
            accent = \"0xff{}\",\n\
            accent_raw = \"{}\",\n\
            bg = \"0xf0{}\",\n\
            fg = \"0xff{}\",\n\
            surface = \"0xff{}\",\n\
            border = \"0xff{}\",\n\
        }}\n",
        &p.accent[1..],
        p.accent,
        &p.bg[1..],
        &p.fg[1..],
        &p.surface[1..],
        &p.border[1..]
    );
    atomic(&home().join(".config/hypr/colors.lua"), hypr_colors)?;

    // 2. Generate Rofi Theme Tokens
    let rofi_theme = format!(
        "/** Zenith Generated Palette Tokens **/\n\
        * {{\n\
            main-bg:            {};\n\
            main-fg:            {};\n\
            main-br:            {};\n\
            main-ex:            {};\n\
            select-bg:          {};\n\
            select-fg:          {};\n\
            accent:             {};\n\
        }}\n",
        p.bg, p.fg, p.border, p.surface, p.selection, p.fg, p.accent
    );
    atomic(&cache().join("theme.rasi"), rofi_theme)?;

    // 3. Generate Foot Terminal Colors
    let foot_colors = format!(
        "[colors-dark]\n\
        foreground={}\n\
        background={}\n\
        regular0=000000\n\
        regular1=ff5555\n\
        regular2=50fa7b\n\
        regular3=f1fa8c\n\
        regular4={}\n\
        regular5=bd93f9\n\
        regular6=8be9fd\n\
        regular7=bbbbbb\n\
        bright0=555555\n\
        bright1=ff6e6e\n\
        bright2=69ff94\n\
        bright3=ffffa5\n\
        bright4={}\n\
        bright5=d6acff\n\
        bright6=a4ffff\n\
        bright7=ffffff\n",
        &p.fg[1..],
        &p.bg[1..],
        &p.accent[1..],
        &p.accent[1..]
    );
    atomic(&home().join(".config/foot/colors.ini"), foot_colors)?;

    Ok(())
}
