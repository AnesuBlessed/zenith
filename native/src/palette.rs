use crate::config::*;
use serde_json::{json, Value};
use std::{fs, path::Path};

/// Zenith palette engine — turns a seed colour into the Material-style token
/// set that `core/Theme.qml` and the picker both consume.

#[derive(Clone, Copy)]
pub struct Hsl {
    pub h: f64,
    pub s: f64,
    pub l: f64,
}

pub fn parse_hex(text: &str) -> Option<(u8, u8, u8)> {
    let t = text.trim().trim_start_matches('#');
    if t.len() != 6 {
        return None;
    }
    let r = u8::from_str_radix(&t[0..2], 16).ok()?;
    let g = u8::from_str_radix(&t[2..4], 16).ok()?;
    let b = u8::from_str_radix(&t[4..6], 16).ok()?;
    Some((r, g, b))
}

pub fn to_hex(r: f64, g: f64, b: f64) -> String {
    let c = |v: f64| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
    format!("#{:02x}{:02x}{:02x}", c(r), c(g), c(b))
}

pub fn rgb_to_hsl(r: u8, g: u8, b: u8) -> Hsl {
    let r = r as f64 / 255.0;
    let g = g as f64 / 255.0;
    let b = b as f64 / 255.0;
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    let l = (max + min) / 2.0;
    if delta < f64::EPSILON {
        return Hsl { h: 0.0, s: 0.0, l };
    }
    let s = if l > 0.5 { delta / (2.0 - max - min) } else { delta / (max + min) };
    let h = if max == r {
        ((g - b) / delta + if g < b { 6.0 } else { 0.0 }) / 6.0
    } else if max == g {
        ((b - r) / delta + 2.0) / 6.0
    } else {
        ((r - g) / delta + 4.0) / 6.0
    };
    Hsl { h: h * 360.0, s, l }
}

fn hue_to_rgb(p: f64, q: f64, mut t: f64) -> f64 {
    if t < 0.0 { t += 1.0 }
    if t > 1.0 { t -= 1.0 }
    if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
    if t < 0.5 { return q }
    if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
    p
}

pub fn hsl_to_hex(h: f64, s: f64, l: f64) -> String {
    let h = ((h % 360.0) + 360.0) % 360.0 / 360.0;
    let s = s.clamp(0.0, 1.0);
    let l = l.clamp(0.0, 1.0);
    if s < f64::EPSILON {
        return to_hex(l, l, l);
    }
    let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let p = 2.0 * l - q;
    to_hex(
        hue_to_rgb(p, q, h + 1.0 / 3.0),
        hue_to_rgb(p, q, h),
        hue_to_rgb(p, q, h - 1.0 / 3.0),
    )
}

struct Scheme {
    saturation: f64,
    hue_shift: f64,
}

fn scheme_for(name: &str) -> Scheme {
    match name {
        "scheme-vibrant" => Scheme { saturation: 0.86, hue_shift: 0.0 },
        "scheme-content" => Scheme { saturation: 0.62, hue_shift: 0.0 },
        "scheme-expressive" => Scheme { saturation: 0.78, hue_shift: 18.0 },
        "scheme-fidelity" => Scheme { saturation: 0.55, hue_shift: -12.0 },
        "scheme-fruit-salad" => Scheme { saturation: 0.74, hue_shift: 105.0 },
        "scheme-neutral" => Scheme { saturation: 0.18, hue_shift: 0.0 },
        "scheme-monochrome" => Scheme { saturation: 0.02, hue_shift: 0.0 },
        "scheme-rainbow" => Scheme { saturation: 0.72, hue_shift: 60.0 },
        _ => Scheme { saturation: 0.56, hue_shift: 0.0 },
    }
}

fn tone(hue: f64, sat: f64, light: f64, chroma: f64) -> String {
    hsl_to_hex(hue, sat * chroma, light)
}

fn palette_for(seed: (u8, u8, u8), scheme: &str, light_mode: bool) -> Value {
    let base = rgb_to_hsl(seed.0, seed.1, seed.2);
    let s = scheme_for(scheme);
    let hue = base.h + s.hue_shift;
    let chroma = s.saturation.max(0.12);
    if light_mode {
        json!({
            "primary": tone(hue, chroma, 0.40, 1.0),
            "onPrimary": "#ffffff",
            "primaryContainer": tone(hue, 0.85, 0.90, chroma),
            "onPrimaryContainer": tone(hue, 0.55, 0.16, chroma),
            "secondary": tone(hue + 8.0, 0.22, 0.42, chroma),
            "tertiary": tone(hue + 60.0, 0.32, 0.42, chroma),
            "surface": tone(hue, 0.30, 0.985, chroma),
            "surfaceContainerLow": tone(hue, 0.30, 0.962, chroma),
            "surfaceContainer": tone(hue, 0.32, 0.938, chroma),
            "surfaceContainerHigh": tone(hue, 0.34, 0.912, chroma),
            "onSurface": tone(hue, 0.35, 0.11, chroma),
            "onSurfaceVariant": tone(hue, 0.20, 0.32, chroma),
            "outline": tone(hue, 0.16, 0.50, chroma),
            "outlineVariant": tone(hue, 0.20, 0.80, chroma),
            "error": "#ba1a1a",
            "warning": "#805600",
            "success": "#216e45",
        })
    } else {
        json!({
            "primary": tone(hue, chroma, 0.82, 0.78),
            "onPrimary": tone(hue, 0.60, 0.18, chroma),
            "primaryContainer": tone(hue, 0.65, 0.40, chroma),
            "onPrimaryContainer": tone(hue, 0.42, 0.94, chroma),
            "secondary": tone(hue + 8.0, 0.26, 0.82, chroma),
            "tertiary": tone(hue + 60.0, 0.40, 0.80, chroma),
            "surface": tone(hue, 0.26, 0.055, chroma),
            "surfaceContainerLow": tone(hue, 0.26, 0.085, chroma),
            "surfaceContainer": tone(hue, 0.28, 0.112, chroma),
            "surfaceContainerHigh": tone(hue, 0.30, 0.148, chroma),
            "onSurface": tone(hue, 0.30, 0.93, chroma),
            "onSurfaceVariant": tone(hue, 0.22, 0.79, chroma),
            "outline": tone(hue, 0.16, 0.62, chroma),
            "outlineVariant": tone(hue, 0.20, 0.30, chroma),
            "error": "#ffb4ab",
            "warning": "#f4c46b",
            "success": "#8bd5a5",
        })
    }
}

/// Reads `appearance.mode` from the QML settings file so an explicit light or
/// dark choice survives palette regeneration.
pub fn preferred_mode() -> String {
    let path = xdg("XDG_CONFIG_HOME", ".config").join("zenith/settings.json");
    if let Ok(raw) = fs::read_to_string(path) {
        if let Ok(value) = serde_json::from_str::<Value>(&raw) {
            if let Some(mode) = value["appearance"]["mode"].as_str() {
                if mode == "light" {
                    return "light".into();
                }
            }
        }
    }
    "dark".into()
}

fn seed_from_image(img: &image::DynamicImage) -> String {
    let thumb = img.resize_exact(48, 48, image::imageops::FilterType::Triangle);
    let rgb = thumb.to_rgb8();
    let mut best = (168u8, 153u8, 230u8);
    let mut best_score = 0.0f64;
    for pixel in rgb.pixels() {
        let q = [pixel[0] / 16 * 16, pixel[1] / 16 * 16, pixel[2] / 16 * 16];
        let hsl = rgb_to_hsl(q[0], q[1], q[2]);
        if hsl.l < 0.18 || hsl.l > 0.90 {
            continue;
        }
        let score = hsl.s * hsl.s * (1.0 - (hsl.l - 0.55).abs());
        if score > best_score {
            best_score = score;
            best = (q[0], q[1], q[2]);
        }
    }
    to_hex(best.0 as f64 / 255.0, best.1 as f64 / 255.0, best.2 as f64 / 255.0)
}

fn cached_seed() -> Option<String> {
    let raw = fs::read_to_string(cache().join("current_seed")).ok()?;
    let seed = raw.trim().to_string();
    parse_hex(&seed).map(|_| seed)
}

/// Seeds a video wallpaper from a decoded frame; falls back to the last working
/// seed when ffmpeg is unavailable so animated walls never reset the theme.
fn video_seed(path: &Path) -> Option<String> {
    if !exists("ffmpeg") {
        return None;
    }
    let frame = cache().join(format!("video-seed-{}.png", std::process::id()));
    let ok = std::process::Command::new("ffmpeg")
        .args(["-y", "-loglevel", "error", "-ss", "1", "-i"])
        .arg(path)
        .args(["-vframes", "1"])
        .arg(&frame)
        .status()
        .map(|status| status.success())
        .unwrap_or(false);
    let seed = if ok {
        image::open(&frame).ok().map(|img| seed_from_image(&img))
    } else {
        None
    };
    let _ = fs::remove_file(&frame);
    seed
}

pub fn extract_seed(path: &Path) -> String {
    if let Ok(img) = image::open(path) {
        return seed_from_image(&img);
    }
    if crate::wallpaper::is_video(path) {
        if let Some(seed) = video_seed(path) {
            return seed;
        }
    }
    cached_seed().unwrap_or_else(|| "#a899e6".into())
}

/// Writes every palette consumer in one transaction.
pub fn write_palette(seed_hex: &str, scheme: &str, mode: &str) -> Result<Value> {
    let seed = parse_hex(seed_hex).ok_or_else(|| error(format!("Invalid seed colour: {seed_hex}")))?;
    let document = json!({
        "mode": if mode == "light" { "light" } else { "dark" },
        "seed": format!("#{:02x}{:02x}{:02x}", seed.0, seed.1, seed.2),
        "scheme": scheme,
        "dark": palette_for(seed, scheme, false),
        "light": palette_for(seed, scheme, true),
    });
    atomic(&state().join("palette.json"), serde_json::to_vec_pretty(&document)?)?;

    // Mirror for the greeter before consumer writes; a bad rofi/foot/hyprlock
    // target must never leave SDDM with stale colors.
    if let Err(err) = write_sddm_palette(&document) {
        eprintln!("zenith-native: SDDM palette mirror skipped: {err}");
    }

    write_consumers(&document)?;
    Ok(document)
}

fn token<'a>(palette: &'a Value, group: &str, key: &str) -> &'a str {
    palette[group][key].as_str().unwrap_or("#000000")
}

fn write_consumers(document: &Value) -> Result {
    let mode = document["mode"].as_str().unwrap_or("dark");
    let group = if mode == "light" { "light" } else { "dark" };
    let accent = token(document, group, "primary");
    let accent_soft = token(document, group, "primaryContainer");
    let bg = token(document, group, "surface");
    let surface = token(document, group, "surfaceContainer");
    let fg = token(document, group, "onSurface");
    let outline = token(document, group, "outlineVariant");
    let border_dark = token(document, group, "outline");

    let lua = format!(
        "-- Zenith generated palette — rewritten by zenith-native on every wallpaper change\n\
         return {{\n\
             accent        = \"0xff{}\",\n\
             accent_subtle = \"0xff{}\",\n\
             border_dark   = \"0xff{}\",\n\
             bg            = \"0xf0{}\",\n\
             fg            = \"0xff{}\",\n\
             surface       = \"0xff{}\",\n\
         }}\n",
        &accent[1..], &accent_soft[1..], &border_dark[1..], &bg[1..], &fg[1..], &surface[1..]
    );
    atomic(&xdg("XDG_CONFIG_HOME", ".config").join("hypr/colors.lua"), lua)?;

    let foot = format!(
        "[colors-dark]\n\
         foreground={}\n\
         background={}\n\
         selection-background={}\n\
         selection-foreground={}\n\
         regular0={}\n\
         regular1=ff6b81\n\
         regular2=5fd38d\n\
         regular3=f5c86b\n\
         regular4={}\n\
         regular5={}\n\
         regular6=7fd6e8\n\
         regular7={}\n\
         bright0={}\n\
         bright1=ff8fa3\n\
         bright2=8ee9b0\n\
         bright3=ffd98a\n\
         bright4={}\n\
         bright5={}\n\
         bright6=a8e8f2\n\
         bright7={}\n",
        &fg[1..], &bg[1..], &accent[1..], &bg[1..], &bg[1..],
        &accent[1..], &accent_soft[1..], &fg[1..], &outline[1..],
        &accent[1..], &accent_soft[1..], &fg[1..]
    );
    atomic(&xdg("XDG_CONFIG_HOME", ".config").join("foot/colors.ini"), foot)?;

    let rasi = format!(
        "/** Zenith generated palette tokens **/\n\
         * {{\n\
             main-bg:   {}e6;\n\
             main-fg:   {};\n\
             main-br:   {}cc;\n\
             main-ex:   {}b3;\n\
             select-bg: {};\n\
             select-fg: {};\n\
         }}\n",
        bg, fg, accent, surface, accent, bg
    );
    atomic(&cache().join("theme-override.rasi"), rasi)?;

    splice_hyprlock(document)?;
    Ok(())
}

/// Writes the shared palette component consumed by the SDDM greeter. Keeping
/// this in /var/lib/zenith means both hyprlock (via hyprlock.conf) and SDDM
/// follow the same generated tokens after every wallpaper change.
fn write_sddm_palette(document: &Value) -> Result {
    let shared = Path::new("/var/lib/zenith");
    if !shared.is_dir() {
        return Ok(());
    }

    let mode = document["mode"].as_str().unwrap_or("dark");
    let group = if mode == "light" { "light" } else { "dark" };
    let qml = format!(
        "import QtQml\n\n\
         QtObject {{\n\
             readonly property color accent: \"{}\"\n\
             readonly property color surface: \"{}\"\n\
             readonly property color onSurface: \"{}\"\n\
             readonly property color onSurfaceVariant: \"{}\"\n\
             readonly property color error: \"{}\"\n\
             readonly property color outlineVariant: \"{}\"\n\
         }}\n",
        token(document, group, "primary"),
        token(document, group, "surfaceContainerHigh"),
        token(document, group, "onSurface"),
        token(document, group, "onSurfaceVariant"),
        token(document, group, "error"),
        token(document, group, "outlineVariant"),
    );
    let path = shared.join("palette.qml");
    if fs::read_to_string(&path).is_ok_and(|existing| existing == qml) {
        return Ok(());
    }
    atomic(&path, qml)
}

/// Splices the generated palette into the managed block of hyprlock.conf so
/// the lock screen follows the rice. Only rewrites when the marker lines are
/// present ("manage-theme-integration.sh hyprlock enable" owns the block);
/// an unmanaged or absent config is left untouched.
fn splice_hyprlock(document: &Value) -> Result {
    const BEGIN: &str = "# >>> ZENITH PALETTE";
    const END: &str = "# <<< ZENITH PALETTE";
    let conf_path = xdg("XDG_CONFIG_HOME", ".config").join("hypr/hyprlock.conf");
    let conf = match fs::read_to_string(&conf_path) {
        Ok(text) => text,
        Err(_) => return Ok(()),
    };
    if !conf.contains(BEGIN) || !conf.contains(END) {
        return Ok(());
    }
    let mode = document["mode"].as_str().unwrap_or("dark");
    let group = if mode == "light" { "light" } else { "dark" };
    let rgb = |key: &str| hex_to_rgb_str(token(document, group, key));
    let block = format!(
        "{BEGIN}\n\
         $accent   = rgb({})\n\
         $base     = rgb({})\n\
         $surface  = rgba({}, 0.75)\n\
         $border   = rgba({}, 0.35)\n\
         $text     = rgb({})\n\
         $muted    = rgb({})\n\
         $critical = rgb({})\n\
         $popup    = rgba({}, 0.92)\n\
         {END}\n",
        rgb("primary"),
        rgb("surface"),
        rgb("surfaceContainer"),
        rgb("outlineVariant"),
        rgb("onSurface"),
        rgb("onSurfaceVariant"),
        rgb("error"),
        rgb("surfaceContainerHigh"),
    );
    let mut updated = String::with_capacity(conf.len() + block.len());
    let mut inside = false;
    for line in conf.lines() {
        if line.contains(BEGIN) {
            updated.push_str(&block);
            inside = true;
            continue;
        }
        if line.contains(END) {
            inside = false;
            continue;
        }
        if !inside {
            updated.push_str(line);
            updated.push('\n');
        }
    }
    atomic(&conf_path, updated)
}

/// "#a899e6" -> "168, 153, 230" (hyprlock's rgb()/rgba() want decimal)
fn hex_to_rgb_str(hex: &str) -> String {
    let digits = hex.strip_prefix('#').unwrap_or(hex);
    if digits.len() != 6 {
        return "0, 0, 0".into();
    }
    let (r, rest) = digits.split_at(2);
    let (g, b) = rest.split_at(2);
    format!("{}, {}, {}",
        u8::from_str_radix(r, 16).unwrap_or(0),
        u8::from_str_radix(g, 16).unwrap_or(0),
        u8::from_str_radix(b, 16).unwrap_or(0))
}

/// Applies the palette for an existing wallpaper file, honouring an explicit
/// colour seed from settings when the user picked "custom colour".
pub fn regenerate_from(path: &Path) -> Result<Value> {
    regenerate(path, true)
}

/// Regenerates from the wallpaper itself, ignoring a stored custom colour. Used
/// when the user explicitly switches the theme source back to the wallpaper.
pub fn regenerate_wallpaper(path: &Path) -> Result<Value> {
    regenerate(path, false)
}

fn regenerate(path: &Path, honor_color: bool) -> Result<Value> {
    let settings = xdg("XDG_CONFIG_HOME", ".config").join("zenith/settings.json");
    let mut seed = extract_seed(path);
    let mut scheme = "scheme-content".to_string();
    if let Ok(raw) = fs::read_to_string(settings) {
        if let Ok(value) = serde_json::from_str::<Value>(&raw) {
            let appearance = &value["appearance"];
            if honor_color && appearance["themeSourceMode"].as_str() == Some("color") {
                if let Some(color) = appearance["themeSourceColor"].as_str() {
                    if parse_hex(color).is_some() {
                        seed = color.to_string();
                    }
                }
            }
            if let Some(name) = value["wallpaper"]["scheme"].as_str() {
                scheme = name.to_string();
            }
        }
    }
    let mode = preferred_mode();
    write_palette(&seed, &scheme, &mode)
}