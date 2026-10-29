# Nice Crash! — notes for Claude

- Godot 4.6.2, GDScript. Almost everything is built in code (scenes are thin). See GDD.md.
- Portrait (720x1280 base, orientation=portrait).
- Scripts: `player.gd` (physics food character: skins, egg cracks, toaster pods, push/grab/yeet, items), `bot.gd` (AI driver: race / survive / guard), `level.gd` (rounds + obstacles, `Level.COURSES`), `projectile.gd` (thrown food, cannonballs, rollers), `main.gd` (game scene: racers, countdown, camera, HUD, results, crash juice), `menu.gd` (skins, round picker), `touch_controls.gd` (joystick + JUMP/GRAB/ACT, layout from `Game.layout`, edit mode), `scenery.gd` (themed backdrop), `props.gd` (model loading/candy look/MultiMesh), `fx.gd` (model-mesh particle bursts), `ui.gd` + `chunky_style.gd` (UI kit), `toon.gd`, `game_state.gd` (autoload `Game`: sounds incl. `assets/kenney/sfx/*`, slowmo, settings, update check).
- The owner wants real assets, not primitive shapes: build world/props from Kenney models via `Props.make("kit/name")`. Need a new model? Add it to `tools/fetch_assets.sh` and run it (GitHub mirror; kenney.nl is blocked). Preview models with `tools/model_sheet.gd`.
- Never use `Tween.set_loops()` with 0/infinite loops: if the target is freed it hangs forever in release builds (guard is debug-only). Animate idle motion in `_process`.
- UI icons: edit `tools/gen_icons.py`, run it, reimport (`svg/scale=2.0` in the .import files).
- Assets: `assets/kenney/` (CC0 models/sounds, OFL font).
- Workflow: the owner wants every finished change built automatically. When work is done and checked, commit on the session branch, then fast-forward `main` to it and push `main` (`git push origin HEAD:main`). That push triggers the APK build, and the in-app update picks it up. Then check that the run went green.
- End every task by telling the owner explicitly whether it's safe to `/clear`: "אפשר לעשות clear" only once everything is committed, pushed to `main` and the build is green. Otherwise say what's still pending.
- CI: `.github/workflows/android.yml` builds a signed APK on every push to main and publishes release `v0.1.<run>`. Build number = run number; in-app update check compares it.
- Signing: `android/release.keystore.enc` (AES, decrypted with secret `KEYSTORE_PASS`, alias `nicecrash`).
- If CI fails, the export log is pushed to branch `ci-logs` (`last-failure.log`) — read it with git.
- Test headless locally: run a SceneTree script that sets `Game.course`, loads `res://scenes/main.tscn` and drives `main.controls.move` / `jump_pressed` / `act_pressed` (wait for `main.running`, the countdown takes ~4 s). New `class_name` scripts need `godot --headless --import` once before `--script` runs see them.
- Screenshots: `apt-get install mesa-vulkan-drivers`, then `xvfb-run godot --rendering-method mobile --resolution 720x1280 --script <shot.gd>` and save `root.get_texture().get_image()`.
