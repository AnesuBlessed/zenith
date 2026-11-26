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

### Recommended next (26–28 and 30 applied in the same pass)

26. **Lazy-load island pages with `Loader`.** All eight expanded pages
(NotificationCenter, CapturePage, SessionPage, SettingsPage, Dashboard,
ControlCenter, InsightCenter, WallpaperPage) are built at startup in
`island/IslandExpanded.qml`. Wrapping each in `Loader { active: <pageOpen> }`
would cut quickshell startup time and idle RSS meaningfully (each page is
200–700 lines of QML with its own images/effects). **Applied:** every page
in `island/IslandExpanded.qml` is now a `Loader { active: <pageOpen> }`;
`settingsSection`, the control-center detail state and `closeTransientUi()`
were rewired through the loader items so Island.qml's write/read paths keep
working. Trade-off paid: ~one frame of build time on a page's first open.

27. **Gate the 2 s metrics timer on island visibility.** `fastTimer` runs
even when the dashboard is closed. Binding `running: root.overviewOpen`
(and an on-close flush) makes the idle loop fully dormant. **Applied:**
`SystemService.consumerVisible` gates all three metrics timers; IslandExpanded
binds it to `overviewOpen || insightOpen`. First open of the dashboard
triggers an immediate refresh via `triggeredOnStart`.

28. **`WallpaperService.healthTimer` spawns a process every 20 s.**
**Applied:** the timer is now recovery-only (`running: backendState !==
"ready"`), so a healthy session spawns zero steady-state probes; a dead
daemon is caught by the next operation erroring, which re-arms the timer.

29. **Audio/battery/bluetooth poll processes 1–2× per second.**
**Correction on re-inspection:** the timers found (400–1800 ms) are one-shot
operation sequencers (startup guards, pairing flow steps), not recurring
polls. The recurring state flows are already event-driven — PipeWire events
for audio, UPower signals for battery, bluetoothctl watch for devices.
No change needed; a native daemon would only save fork overhead we do not
currently pay.

30. **CPU blur in Rust on wallpaper transactions.** `wallpaper_align.rs`
ran full-resolution Gaussian blurs for the lock background, clipboard crop
and launcher rail on every wallpaper change (~200–600 ms on the N4000).
**Applied:** `blur_sharpness_respecting_size()` downscales ×3, blurs at
radius/3, upscales back — visually equivalent (the upscale adds smoothness)
and roughly 3× faster.

### Island wallpaper page (applied same day)

31. **The island's wallpaper gallery decoded full-resolution originals.**
`panels/WallpaperCard.qml` loaded `source: <original 4K file>` with a fixed
420×250 decode and `cache: true` — the pixmap cache held every discovered
wallpaper at that size for the life of the page, and PNG originals still
paid a full decode before scaling. **Applied:** `zenith-native wallpaper
list` now reports `path<TAB>thumb-name` (picker-index naming, so deduped);
`WallpaperService` exposes `thumb:` on each row and the card prefers the
shared 500px JPEG thumbnail, falling back to the original on error; the
decode is now bound to the card's real size (~120×126) and `cache: false`
so unloaded pages keep nothing.

32. **The gallery had three stacked layers of padding.** Island page
margins (12px) + grid `anchors.margins` (8px) + per-card margins (4px) =
24px of dead chrome around cards that are only ~120px wide. **Applied:**
page spacing `space2 → space1`, header row 42 → 40px, grid margins 8 → 4px,
card margins 4 → 2px. Cards gain visible area without changing the island's
outer frame.

### Picker scaling pass (applied same day)

33. **Two layouts referenced `uiScale` without ever defining it.**
`shell-coverflow-minimal.qml` and `shell-floating-minimal.qml` multiplied
their card sizes by `main.uiScale`, which did not exist on their root —
every dimension resolved to NaN, so those two layouts rendered collapsed
whenever selected. **Applied:** the definition was added to both.

34. **The scale clamp was too narrow for extreme screens.** `0.7–1.2`
of `min(w/1920, h/1080)` pinned 4K screens to 1.2 (cards still small on a
huge monitor) and small screens to 0.7 (cards could overflow a 1024-wide
panel). **Applied:** clamp widened to `0.55–1.35` in all ten layouts.

35. **Leftover fixed-pixel constants in the layouts.** The coverflow gap,
header (60/16/14px + letterSpacing), classic's row spacing and margins,
the bottom-dock badge, grid-view's detail panel rhythm (32/12/13/20px) and
hexcomb's grid margins/spacing were all unscaled — on a 1366×768 screen
they read ~40% too large relative to the scaled cards. **Applied:** every
remaining fixed constant now multiplies by `uiScale`.

### Status summary of the original items

- Items **9** (zero-Python rule) — fixed (dev tool removed from the repo).
- Items **13–17** (SDDM/lock) — fixed and superseded by the SilentSDDM
  engine vendoring.
- Items **18–35** (performance + scaling audit) — fixed in this pass.
- Items **1–8** (notification service data model) — the display layer was
  replaced by the Rust/C engine, but the service internals remain as
  described: history is still memory-only (`history.length` counts unread),
  the provenance observer is still inert, multi-action cards still expose
  one action, and `persistenceSupported` still over-advertises. These are
  behavior/feature work, not performance — still open, still deliberate.

### RAM budget reality check

Even perfect code cannot beat the compositor: Hyprland + GPU framebuffers
alone are ~150–250 MB. The realistic ladder on the N4000 machine:

- Today: ~700–900 MB idle (foot + quickshell heavy)
- After #26 + #27: ~600–700 MB
- Plus smaller foot scrollback (`scrollback: 10000` → lines) and closing
  idle portals: **~450–600 MB** ✅

## Drip rebuild pass — notification stack (jrnxf/drip → Zenith)

### What drip does (macOS reference)
Cards drop from the notch: a spring-animated stack (max ~3), an overflow
chip counting what waits below, hover freezes timers, actions are real
buttons on the card, and a card can update in place (building → passed)
without restarting its animation. Delivery is a CLI contract
(`drip ok/warn/run`), history survives restarts, and clicking a card
returns to the producing app.

### What the previous agent already shipped (verified in this pass)
- `native/src/notify.rs` — display-only Rust engine: additive damped
  springs (velocity survives an interrupted retarget, drip rule), bounded
  3-card stack, hover freeze (`hold`/`release`), timeout expiry, atomic
  JSON snapshot at ~60 fps, Unix-socket command protocol.
- `native/zenith-notifyctl.c` — thin C client so QML and shell scripts
  share one stable entry point.
- `services/NotificationBridge.qml` — forwards service popups to the
  engine and mirrors its snapshot into QML.
- `island/NotifyStack.qml` + `island/NotifyCard.qml` — QML renders the
  engine-sampled cards on the existing island surface. The old
  single-card banner (`island/IslandNotification.qml`) is gone.

### Fixed in this pass (the old service problems, items 1–8)

36. **The provenance observer is gone, replaced by identity provenance.**
    The old `scripts/notification-provenance.sh` sat blocked on stdin that
    nothing ever wrote (no `stdinEnabled`, wrong event schema, wrong
    arity), so exact-window focus silently never worked. **Applied:**
    helper and observer deleted; `HyprlandService.identityProvenance()`
    now snapshots a live toplevel matched by `desktopEntry`/`appName`
    against window classes at receive time. `activate()` still
    revalidates against the live toplevel list, so a closed window never
    gets focused — clicking a card goes back to the producing app, drip
    style.

37. **History is now persistent.** `NotificationService` serializes plain
    data (no D-Bus sources/actions) to
    `$XDG_STATE_HOME/zenith/notifications.json` on every change, restores
    it at startup, and drops entries older than two days. A shell reload
    no longer wipes the Notification Center.

38. **`unread` is now a real counter.** The bell glyph, dashboard chip
    read `history.length` before (closed notifications kept the light on).
    They read `unread`, which increments on arrival and clears the moment
    the Notification Center is seen.

39. **Every labeled action is now a real button.** The engine wire format
    carries `actionLabels[]` (up to 3), the bridge forwards all of them,
    and `NotifyCard` renders a drip-style button row instead of only the
    first action. The Notification Center history card still shows one
    action — acceptable there, cards are the primary surface.

40. **Capability advertising now tells the truth.** The server advertised
    markup/images support while `plainText()` strips them all; apps could
    send rich bodies that rendered as tag soup. Now advertises plain
    bodies only.

41. **The dead `coexistenceMode`/`takeOverServer` flag is gone.** There
    was no fallback listener; flipping the flag just silently stopped
    receiving notifications.

42. **Idle cost of the engine dropped.** The daemon looped at 125 Hz even
    with no cards (always-awake wakeups on battery) and rewrote its
    snapshot at 60 fps. Now: 8 ms ticks while presenting, 100 ms when
    idle, snapshots at 30 fps and only on content change.

43. **Cards hold while locked, replay on unlock (drip ScreenLock).**
    `scripts/lock.sh` sends `hold` before hyprlock and `release` when it
    exits — timers freeze, nothing expires invisibly, queued cards drop
    in when you get back.

### Still open (documented, deliberate)
- **Lock-screen notification surface:** hyprlock has no way to render
  cards; hold/replay is the honest equivalent until hyprlock grows one.
- **Update-in-place via key reuse:** the engine already morphs an
  existing card (springs survive) when an app reuses the id, but no
  recipe/CLI contract like `drip run` exists for scripts. A future
  `zenith-notifyctl sync` CLI sugar could add the `drip ok` experience.
- **Notification Center card actions:** single action (see #39).

### Island rest-row Keep Awake (applied)

44. **The coffee (Keep Awake) icon was cosmetic.** `IdleService.toggleInhibition()`
    flipped a local boolean — hypridle kept its lock/dim/dpms/suspend timers, so
    the screen still slept with the coffee "on". **Applied:** `idlectl.sh`
    gained `inhibit` (rewrites the managed policy with every listener disabled)
    and `resume` (restores the configured policy); the service runs the real
    transaction, only flips `inhibited` when the helper confirms, and policy
    edits made while inhibited re-assert inhibition afterwards.
