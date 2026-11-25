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
