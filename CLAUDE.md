# Nice Crash! — notes for Claude

- Godot 4.6.2, GDScript. Almost everything is built in code (scenes are thin). See GDD.md.
- Scripts: `player.gd` (physics character), `level.gd` (course builder), `main.gd` (game scene, camera, HUD, crash juice), `menu.gd`, `touch_controls.gd`, `toon.gd`, `game_state.gd` (autoload `Game`: sounds, slowmo, update check).
- Assets: `assets/kenney/` (CC0 models/sounds, OFL font).
- CI: `.github/workflows/android.yml` builds a signed APK on every push to main and publishes release `v0.1.<run>`. Build number = run number; in-app update check compares it.
- Signing: `android/release.keystore.enc` (AES, decrypted with secret `KEYSTORE_PASS`, alias `nicecrash`).
- If CI fails, the export log is pushed to branch `ci-logs` (`last-failure.log`) — read it with git.
- Test headless locally: run a SceneTree script that loads `res://scenes/main.tscn` and drives `main.controls.move`.
