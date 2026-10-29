# Nice Crash! — notes for Claude

- Godot 4.6.2, GDScript. Almost everything is built in code (scenes are thin). See GDD.md.
- Portrait (720x1280 base, orientation=portrait).
- Scripts: `player.gd` (physics character), `level.gd` (course builder), `main.gd` (game scene, camera, HUD, pause/finish, crash juice), `menu.gd`, `touch_controls.gd` (layout from `Game.layout`, edit mode), `scenery.gd` (backdrop), `ui.gd` + `chunky_style.gd` (UI kit), `toon.gd`, `game_state.gd` (autoload `Game`: sounds, slowmo, settings, update check).
- Never use `Tween.set_loops()` with 0/infinite loops: if the target is freed it hangs forever in release builds (guard is debug-only). Animate idle motion in `_process`.
- UI icons: edit `tools/gen_icons.py`, run it, reimport (`svg/scale=2.0` in the .import files).
- Assets: `assets/kenney/` (CC0 models/sounds, OFL font).
- Workflow: the owner wants every finished change built automatically. When work is done and checked, commit on the session branch, then fast-forward `main` to it and push `main` (`git push origin HEAD:main`). That push triggers the APK build, and the in-app update picks it up. Then check that the run went green.
- End every task by telling the owner explicitly whether it's safe to `/clear`: "אפשר לעשות clear" only once everything is committed, pushed to `main` and the build is green. Otherwise say what's still pending.
- CI: `.github/workflows/android.yml` builds a signed APK on every push to main and publishes release `v0.1.<run>`. Build number = run number; in-app update check compares it.
- Signing: `android/release.keystore.enc` (AES, decrypted with secret `KEYSTORE_PASS`, alias `nicecrash`).
- If CI fails, the export log is pushed to branch `ci-logs` (`last-failure.log`) — read it with git.
- Test headless locally: run a SceneTree script that loads `res://scenes/main.tscn` and drives `main.controls.move`.
- Screenshots: `apt-get install mesa-vulkan-drivers`, then `xvfb-run godot --rendering-method mobile --resolution 720x1280 --script <shot.gd>` and save `root.get_texture().get_image()`.
