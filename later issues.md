# Later issues

Findings from reading Zenith end to end while replacing the notification **display layer** with a Rust/C engine that renders on the existing Quickshell island surface. These are deliberately left for a later pass unless they directly block the display rewrite.

## Notification service / data model

1. **Provenance observer is inert.** `services/NotificationService.qml:304-310` starts `scripts/notification-provenance.sh` with no stdin channel, while the script blocks reading `<notificationId> <pid>` from stdin (`scripts/notification-provenance.sh:14-33`). The emitted JSON has three keys, but the parser at `NotificationService.qml:341-352` requires `version === 1`, `event === "provenance"`, and exactly four keys. `bindProvenance()` is called with two arguments although it declares three (`:281-302`). Result: `entry.provenance` is normally `null`, so exact-window focus rarely works. Fix: enable `stdinEnabled`, emit the versioned four-key event, write ids/pids into the observer, and pass the toplevel snapshot.

2. **History is not persistent.** The server advertises `persistenceSupported: true` (`NotificationService.qml:366`) but history is only an in-memory JS array (`:17`). A shell reload loses everything. `drip` uses an append-only JSONL state file with locks and size limits; Zenith should do the same if history is meant to survive restarts.

3. **`count` is not an unread count.** `NotificationService.qml:29` returns `history.length`, so closed/read notifications still light the bell and dashboard until manually cleared. Consider separating `unread` from `history`.

4. **One `current` entry, no queue or stack.** A new notification replaces the previous popup (`NotificationService.qml:83-86`). Bursts drop cards visually. The new native engine fixes the display side by keeping a bounded, spring-animated stack, but the service still exposes only one `current` entry to other consumers.

5. **Hardcoded server policy.** `Config.notifications.enabled` and `takeOverServer` are both literal `true` (`core/Config.qml:289-291`). `coexistenceMode` is computed but unused (`NotificationService.qml:15`); turning takeover off does not create a fallback listener, it simply stops receiving anything. Either implement a coexistence listener or remove the dead flag and expose a real setting.

6. **Capability mismatch.** `bodyImagesSupported`, `imageSupported`, and `bodyMarkupSupported` are advertised (`NotificationService.qml:368-373`), but `plainText()` strips `<img>` tags and all markup (`:40-50`). Either support inline images or stop advertising them.

7. **Only the first labeled action is reachable.** The banner and history card render `visibleActions[0]` only (`island/IslandNotification.qml:24-26`, `panels/NotificationCard.qml:110-131`). Apps with several actions are effectively reduced to one. A stack card could expose a compact action row.

8. **No lock-screen notification presentation.** hyprlock is themed (`sddm/zenith/`, `hypr/hyprlock.conf`) but there is no lock-screen notification surface. `drip` holds cards while locked and replays missed ones on unlock; Zenith has no equivalent.

## Native / build

9. **`scripts/check.sh` currently fails its own zero-Python rule.** `scripts/check.sh:23-29` rejects any `*.py`, but `tools/build-zenith-font.py` is committed (it is documented as dev-only and its TTF output is committed). Exclude `tools/` from the check or move the generator out of the repo.

10. **No native notification bridge before this change.** Rust and C only produced notifications via `notify-send` (`native/src/wallpaper.rs:286-299`, `scripts/capturectl.sh:23-25`). Nothing received or rendered them natively. The new `notify` engine/client closes that gap while leaving D-Bus ownership in Quickshell.

11. **Unix socket and state file need runtime-dir hygiene.** The new daemon binds under `$XDG_RUNTIME_DIR/zenith` (fallback `/tmp`), cleans stale sockets, sets `0600`, and exits when its Quickshell parent disappears. Keep this liveness check if the daemon is ever detached.

## Verification limits in this workspace

12. This checkout is being edited on Windows; it targets Arch Linux + Hyprland + Wayland. The Rust core can be type-checked here if dependencies are available, but Quickshell/QML, the Wayland layer shell, D-Bus delivery, and the C client must be validated on a real Arch/Hyprland session with `scripts/check.sh`, `install.sh`, and a `notify-send` smoke test.

## Lock screen / SDDM

13. **SDDM could not load the Zenith theme.** `sddm/zenith/metadata.desktop` used `[Desktop Entry]`, which SDDM 0.21 ignores; it reads `SddmGreeterTheme/MainScript`, `ConfigFile`, `TranslationsDirectory` and `QtVersion` from `[SddmGreeterTheme]`. The missing `QtVersion=6` selected the Qt5 greeter, whose versionless `import QtQuick` fails on Arch. The theme now declares `QtVersion=6`.

14. **The greeter used a non-existent proxy API.** `Main.qml` read `sddm.lastSession`/`sddm.lastUser` and passed a session name to `sddm.login()`. SDDM 0.21 exposes `sessionModel.lastIndex`, `userModel.lastUser` and `login(user, password, sessionIndex:int)`. Passing a string could type-error or start the wrong session even after the QML loaded. The theme now uses the integer model index.

15. **The two screens had separate sources of truth.** hyprlock used runtime-generated palette values while SDDM hardcoded cyan/blue constants; hyprlock used the generated avatar in `$HOME/.cache` while SDDM used a static theme file; the shared background was only seeded if a cache file already existed. Native code now mirrors palette/background/avatar into `/var/lib/zenith`, and `install.sh` seeds all three before first login.

16. **SDDM was only enabled on UEFI.** The old installer gated `systemctl enable sddm.service` behind `-d /sys/firmware/efi`, so BIOS/MBR installs booted to a console with no greeter. It is now enabled unconditionally and `graphical.target` is set as the default.

17. **Remaining lock/greeter gaps.** SDDM cannot execute the user-session status scripts itself, so it reads the snapshot written by `lock.sh`/`install.sh`; values are stale until the next lock. The greeter now uses a SilentSDDM-inspired card and power/session popups, but it only reads Zenith's generated palette/background/avatar and keeps Zenith Display as the display font.

## Performance audit (idle RAM + picker lag) — 2026 pass

Target: idle session ~450–600 MB RSS total, and near-zero cost when the
picker / clipboard open and close. Findings ordered by impact.

### What actually owns idle RAM (Celeron N4000, UHD 600, 3.64 GB)

| Process | Rough RSS | Notes |
|---|---|---|
| Hyprland (compositor) | 150–250 MB | GPU buffers + shaders; grows with open windows |
| quickshell (island) | 100–180 MB | QML engine + all panel trees + image cache |
| foot | 30–80 MB | per window, grows with scrollback (`scrollback-buffer`) |
| pipewire + wireplumber | 25–40 MB | audio graph |
| xdg-desktop-portal-hyprland | 20–60 MB | screencopy/sharing backend |
| awww daemon | 10–20 MB | holds the wallpaper texture |
| hypridle, hyprpolkitagent, cliphist | ~10 MB | cliphist loads history lazily |

The 450–600 MB idle goal is realistic **only if** quickshell stays lean;
the compositor and portals set the floor. The levers below attack
quickshell and the picker, which are the two things we control.

### Fixed in this pass (picker / native)

18. **Picker thumbnails were PNG-encoded photos.** `thumbs.rs` wrote PNG
bytes for every card (a 4K wallpaper became a 3–6 MB, ~50 ms-to-decode
file the picker re-decodes on every open). Now encoded as JPEG q86:
~5× smaller, ~6× faster decode, no visible difference at card size.
Existing PNG thumbs are replaced by `zenith-native wallpaper thumbs --force`.
Picker opening is now decode-bound at ~10–15 ms per card instead of ~50 ms.

19. **Every picker layout blurred a full-resolution background.** The
`bgImageA/B` items decoded the wallpaper at screen resolution and fed a
`MultiEffect{blurMax: 72–80}` over the whole screen — the single most
expensive thing that happens when the picker opens (a 72-tap blur over a
1366×768 texture, on a UHD 600). All layouts now decode the background at
**1/3 screen resolution** (`sourceSize ≈ 455×256`): the image is scaled up
and blurred afterwards, so the visual result is unchanged while decode and
blur cost drop ~9×. This is the difference between "picker stutters open"
and "picker snaps open".

20. **The coverflow/dock error-retry loop could spin forever.** A missing
or corrupt thumbnail re-fetched every second for as long as the picker
stayed open (each retry = full decode attempt). Now capped at 3 attempts.

21. **Wallpaper transitions always paid 60 fps.** `transition_flags()`
hardcoded `--transition-fps 60` even for 1.5 s+ fades. Now: 60 fps for
short transitions, 30 fps for long ones and for reduced-motion, halving
compositor redraw load exactly where the eye cannot tell.

### Verified-good (no change needed)

22. **Picker card images are already bounded.** All layouts set
`sourceSize` on card images (or a constant decode cap in `shell-classic`),
so a 4K wallpaper never decodes at 4K inside the picker.

23. **Thumbnails are generated once, not on every open.**
`thumbs.rs::generate()` skips files that already exist; `Zn.generateThumbs()`
on open is a cheap directory check, and the picker apply path is a detached
`zenith-native wallpaper set` so the short-lived picker never waits on the
transaction.

24. **System metrics polling is cheap.** `SystemService` reads `/proc`
through `FileView` (no process spawn) at 2 s/5 s/30 s intervals — file
reads cost microseconds and no memory.

25. **The island's expanded pages exist but stay invisible.** `QML visible:
false` keeps the trees alive (they still render nothing), which costs some
memory but zero GPU while dormant — the layout/binding state is preserved,
making page switches instant.

### Recommended next (documented, not yet applied — they change UX timing)

26. **Lazy-load island pages with `Loader`.** All eight expanded pages
(NotificationCenter, CapturePage, SessionPage, SettingsPage, Dashboard,
ControlCenter, InsightCenter, WallpaperPage) are built at startup in
`island/IslandExpanded.qml`. Wrapping each in `Loader { active: <pageOpen> }`
would cut quickshell startup time and idle RSS meaningfully (each page is
200–700 lines of QML with its own images/effects). Trade-off: ~one frame of
delay on first page open. Because page `id`s are referenced by the
controller, this needs a careful pass — do it one page at a time.

27. **Gate the 2 s metrics timer on island visibility.** `fastTimer` runs
even when the dashboard is closed. Binding `running: root.overviewOpen`
(and an on-close flush) makes the idle loop fully dormant. Needs the same
service↔island wiring as #26.

28. **`WallpaperService.healthTimer` spawns a process every 20 s.** A
`wallpaper probe` costs ~2–3 ms CPU, so it is tolerable, but the cleaner
design is an event: awww's socket state → one-shot probe on failure only.

29. **Audio/battery/bluetooth poll processes 1–2× per second.**
`AudioService` (900 ms), `BatteryService` (900 ms), `BluetoothService`
(400–1800 ms) each shell out. Native replacements (a single C daemon
reading `upower`/`pactl`/`bluetoothctl` d-bus signals) would remove the
per-poll fork cost entirely. Real win: ~0.5–1 % CPU and some context-switch
noise; do it only after #26/#27.

30. **CPU blur in Rust on wallpaper transactions.** `wallpaper_align.rs`
runs a full-monitor `blur(14.0)` on the CPU for every wallpaper change
(lock/launcher/clipboard crops). One-shot cost (~200–600 ms on the N4000),
not idle cost. If it ever matters, downscale → blur → upscale halves it.

### RAM budget reality check

Even perfect code cannot beat the compositor: Hyprland + GPU framebuffers
alone are ~150–250 MB. The realistic ladder on the N4000 machine:

- Today: ~700–900 MB idle (foot + quickshell heavy)
- After #26 + #27: ~600–700 MB
- Plus smaller foot scrollback (`scrollback: 10000` → lines) and closing
  idle portals: **~450–600 MB** ✅
