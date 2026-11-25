//! Display-only notification engine.
//!
//! Quickshell still owns the freedesktop D-Bus NotificationServer and the
//! history. This module owns the transient island *presentation*: a bounded,
//! spring-animated stack, hover freezing and timeout expiry. It is fed by the
//! QML bridge, writes an atomic JSON snapshot, and is driven from QML by the
//! small C client in `native/zenith-notifyctl.c`.

use crate::config::{atomic, error, Result};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    env, fs,
    io::{BufRead, BufReader, ErrorKind, Write},
    os::unix::{fs::PermissionsExt, net::UnixListener, net::UnixStream},
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant},
};

const MAX_VISIBLE: usize = 3;
const TICK_MS: u64 = 8;
const SNAPSHOT_MS: u64 = 16;

fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn runtime_zenith_dir() -> PathBuf {
    runtime_dir().join("zenith")
}

fn socket_path() -> PathBuf {
    runtime_zenith_dir().join("notify.sock")
}

fn state_path() -> PathBuf {
    runtime_zenith_dir().join("notify-state.json")
}

#[derive(Clone)]
struct SpringPart {
    value: f64,
    target: f64,
    velocity: f64,
}

/// Additive damped spring. A new target adds a part instead of restarting the
/// existing ones, so velocity survives an interrupted animation (drip rule).
#[derive(Clone)]
struct Spring {
    parts: Vec<SpringPart>,
    stiffness: f64,
    damping: f64,
}

impl Spring {
    fn new(value: f64, stiffness: f64, damping: f64) -> Self {
        Self {
            parts: vec![SpringPart {
                value,
                target: value,
                velocity: 0.0,
            }],
            stiffness,
            damping,
        }
    }

    fn value(&self) -> f64 {
        self.parts.iter().map(|part| part.value).sum()
    }

    fn retarget(&mut self, target: f64) {
        for part in &mut self.parts {
            part.target = 0.0;
        }
        self.parts.push(SpringPart {
            value: 0.0,
            target,
            velocity: 0.0,
        });
    }

    fn step(&mut self, dt: f64) {
        for part in &mut self.parts {
            let accel = -self.stiffness * (part.value - part.target)
                - self.damping * part.velocity;
            part.velocity += accel * dt;
            part.value += part.velocity * dt;
        }
        self.parts.retain(|part| {
            (part.target - part.value).abs() > 0.0005
                || part.velocity.abs() > 0.0005
                || part.target.abs() > 0.0005
        });
    }
}

#[derive(Clone)]
struct Card {
    key: String,
    id: u64,
    timestamp: i64,
    app: String,
    title: String,
    body: String,
    icon: String,
    image: String,
    critical: bool,
    action_label: String,
    width: f64,
    height: f64,
    gap: f64,
    timeout_ms: u64,
    born: Instant,
    y: Spring,
    opacity: Spring,
    scale: Spring,
    target_y: f64,
    target_opacity: f64,
    target_scale: f64,
}

fn json_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn json_number(value: &Value, key: &str, fallback: f64) -> f64 {
    value
        .get(key)
        .and_then(Value::as_f64)
        .unwrap_or(fallback)
}

fn card_from_value(value: &Value) -> Card {
    let id = value.get("id").and_then(Value::as_u64).unwrap_or(0);
    let timestamp = value.get("timestamp").and_then(Value::as_i64).unwrap_or(0);
    let key = {
        let supplied = json_string(value, "key");
        if supplied.is_empty() {
            format!("{id}:{timestamp}")
        } else {
            supplied
        }
    };

    Card {
        key,
        id,
        timestamp,
        app: json_string(value, "app"),
        title: json_string(value, "title"),
        body: json_string(value, "body"),
        icon: json_string(value, "icon"),
        image: json_string(value, "image"),
        critical: value.get("critical").and_then(Value::as_bool).unwrap_or(false),
        action_label: json_string(value, "actionLabel"),
        width: json_number(value, "width", 720.0),
        height: json_number(value, "height", 74.0),
        gap: json_number(value, "gap", 8.0),
        timeout_ms: json_number(value, "timeout", 5000.0).max(1.0) as u64,
        born: Instant::now(),
        // Cards drop in from above the island and settle at their slot.
        y: Spring::new(-90.0, 260.0, 26.0),
        opacity: Spring::new(0.0, 420.0, 38.0),
        scale: Spring::new(0.92, 320.0, 30.0),
        target_y: -90.0,
        target_opacity: 0.0,
        target_scale: 0.92,
    }
}

fn retarget(spring: &mut Spring, current: &mut f64, target: f64) {
    if (*current - target).abs() > 0.001 {
        spring.retarget(target);
        *current = target;
    }
}

#[derive(Default)]
struct Engine {
    cards: Vec<Card>,
    revision: u64,
    frozen: bool,
    expired: Vec<Value>,
}

impl Engine {
    fn sync(&mut self, incoming: &[Value]) {
        let previous: HashMap<String, Card> = self
            .cards
            .drain(..)
            .map(|card| (card.key.clone(), card))
            .collect();
        let mut next = Vec::with_capacity(incoming.len());

        for value in incoming {
            let fresh = card_from_value(value);
            if let Some(mut existing) = previous.get(&fresh.key).cloned() {
                existing.app = fresh.app;
                existing.title = fresh.title;
                existing.body = fresh.body;
                existing.icon = fresh.icon;
                existing.image = fresh.image;
                existing.critical = fresh.critical;
                existing.action_label = fresh.action_label;
                existing.width = fresh.width;
                existing.height = fresh.height;
                existing.gap = fresh.gap;
                existing.timeout_ms = fresh.timeout_ms;
                next.push(existing);
            } else {
                next.push(fresh);
            }
        }
        self.cards = next;
    }

    fn tick(&mut self, dt: f64) {
        if self.frozen {
            return;
        }

        let step = |spring: &mut Spring| spring.step(dt);
        let mut expired_keys = Vec::new();

        for (index, card) in self.cards.iter_mut().enumerate() {
            let slot = (index as f64) * (card.height + card.gap);
            let visible = index < MAX_VISIBLE;
            retarget(&mut card.y, &mut card.target_y, slot);
            retarget(
                &mut card.opacity,
                &mut card.target_opacity,
                if visible { 1.0 } else { 0.0 },
            );
            retarget(
                &mut card.scale,
                &mut card.target_scale,
                if visible { 1.0 - index as f64 * 0.025 } else { 0.86 },
            );
            step(&mut card.y);
            step(&mut card.opacity);
            step(&mut card.scale);

            if card.born.elapsed().as_millis() >= card.timeout_ms as u128 {
                expired_keys.push((card.id, card.timestamp));
            }
        }

        if !expired_keys.is_empty() {
            self.revision = self.revision.wrapping_add(1);
            self.cards.retain(|card| {
                !expired_keys
                    .iter()
                    .any(|(id, timestamp)| card.id == *id && card.timestamp == *timestamp)
            });
            for (id, timestamp) in expired_keys {
                self.expired.push(json!({ "id": id, "timestamp": timestamp }));
            }
        }
    }

    fn snapshot(&self) -> Value {
        let cards: Vec<Value> = self
            .cards
            .iter()
            .enumerate()
            .map(|(index, card)| {
                json!({
                    "key": card.key,
                    "id": card.id,
                    "timestamp": card.timestamp,
                    "app": card.app,
                    "title": card.title,
                    "body": card.body,
                    "icon": card.icon,
                    "image": card.image,
                    "critical": card.critical,
                    "actionLabel": card.action_label,
                    "x": 0.0,
                    "y": card.y.value(),
                    "width": card.width,
                    "height": card.height,
                    "opacity": card.opacity.value().clamp(0.0, 1.0),
                    "scale": card.scale.value().clamp(0.7, 1.0),
                    "depth": index,
                })
            })
            .collect();

        let result = json!({
            "revision": self.revision,
            "active": !self.cards.is_empty() || !self.expired.is_empty(),
            "frozen": self.frozen,
            "cards": cards,
            "overflow": self.cards.len().saturating_sub(MAX_VISIBLE),
            "expired": self.expired,
        });
        result
    }

    fn clear_expired(&mut self) {
        self.expired.clear();
    }

    fn handle(&mut self, cmd: &str, payload: &Value) -> Value {
        match cmd {
            "sync" => {
                if let Some(cards) = payload.get("cards").and_then(Value::as_array) {
                    self.sync(cards);
                    self.revision = self.revision.wrapping_add(1);
                }
                json!({ "ok": true, "cards": self.cards.len() })
            }
            "hold" => {
                self.frozen = true;
                self.revision = self.revision.wrapping_add(1);
                json!({ "ok": true })
            }
            "release" => {
                self.frozen = false;
                self.revision = self.revision.wrapping_add(1);
                json!({ "ok": true })
            }
            "clear" => {
                self.cards.clear();
                self.revision = self.revision.wrapping_add(1);
                json!({ "ok": true })
            }
            "dismiss" => {
                let id = payload.get("id").and_then(Value::as_u64).unwrap_or(0);
                let timestamp = payload.get("timestamp").and_then(Value::as_i64).unwrap_or(0);
                let before = self.cards.len();
                self.cards
                    .retain(|card| card.id != id || card.timestamp != timestamp);
                if self.cards.len() != before {
                    self.revision = self.revision.wrapping_add(1);
                }
                json!({ "ok": true })
            }
            "ping" => json!({ "ok": true, "cards": self.cards.len() }),
            _ => json!({ "ok": false, "error": "unknown command" }),
        }
    }
}

fn parent_alive() -> bool {
    let stat = match fs::read_to_string("/proc/self/stat") {
        Ok(value) => value,
        // Non-Linux or unusual procfs: let the QML Process own the lifetime.
        Err(_) => return true,
    };
    let tail = match stat.rfind(')') {
        Some(index) => &stat[index + 1..],
        None => return true,
    };
    let parent = tail
        .split_whitespace()
        .nth(1)
        .and_then(|value| value.parse::<u32>().ok());

    match parent {
        Some(1) | None => false,
        Some(pid) => Path::new(&format!("/proc/{pid}")).exists(),
    }
}

/// Run the background presentation engine. Called as `zenith-native notify daemon`.
pub fn daemon() -> Result {
    let dir = runtime_zenith_dir();
    fs::create_dir_all(&dir)?;
    let sock = socket_path();

    // A second shell must not take over an already running stack.
    if UnixStream::connect(&sock).is_ok() {
        return Err(error("notify daemon is already running"));
    }
    let _ = fs::remove_file(&sock);
    let listener = UnixListener::bind(&sock)?;
    fs::set_permissions(&sock, fs::Permissions::from_mode(0o600))?;
    listener.set_nonblocking(true)?;

    let target = state_path();
    let mut engine = Engine::default();
    let mut last = Instant::now();
    let mut since_snapshot = Duration::ZERO;
    let mut last_snapshot = String::new();

    loop {
        if !parent_alive() {
            break;
        }

        match listener.accept() {
            Ok((stream, _)) => {
                let response = {
                    let mut reader = BufReader::new(&stream);
                    let mut line = String::new();
                    if reader.read_line(&mut line).unwrap_or(0) == 0 {
                        json!({ "ok": false, "error": "empty request" })
                    } else {
                        let request: Value = serde_json::from_str(line.trim())
                            .unwrap_or_else(|_| json!({ "cmd": "ping" }));
                        let cmd = request
                            .get("cmd")
                            .and_then(Value::as_str)
                            .unwrap_or("ping")
                            .to_string();
                        if cmd == "quit" {
                            break;
                        }
                        engine.handle(&cmd, &request)
                    }
                };
                let mut writer = stream;
                let _ = writer.write_all(response.to_string().as_bytes());
                let _ = writer.write_all(b"\n");
                let _ = writer.flush();
            }
            Err(err) if err.kind() == ErrorKind::WouldBlock => {}
            Err(err) => return Err(err.into()),
        }

        let now = Instant::now();
        let elapsed = now.duration_since(last);
        last = now;
        engine.tick(elapsed.as_secs_f64().min(0.05));

        since_snapshot += elapsed;
        if since_snapshot >= Duration::from_millis(SNAPSHOT_MS) {
            let snapshot = engine.snapshot().to_string();
            if snapshot != last_snapshot {
                atomic(&target, snapshot.as_bytes())?;
                engine.clear_expired();
                last_snapshot = snapshot;
            }
            since_snapshot = Duration::ZERO;
        }
        thread::sleep(Duration::from_millis(TICK_MS));
    }

    let _ = fs::remove_file(&sock);
    Ok(())
}

/// Print the last snapshot for debugging: `zenith-native notify snapshot`.
pub fn snapshot() -> Result {
    let raw = fs::read_to_string(state_path()).unwrap_or_else(|_| "{}".into());
    println!("{raw}");
    Ok(())
}
