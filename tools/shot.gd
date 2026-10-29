extends SceneTree
## Dev tool: screenshots of a level. Saves <out>_play.png (the game camera
## a few seconds after GO, a bot driving you) and <out>_top.png (bird's-eye
## view of the whole level).
##   xvfb-run godot --rendering-method mobile --resolution 720x1280 --script tools/shot.gd -- adventure meadow /tmp/meadow 6
##   ... -- party sumo /tmp/sumo 3
##   ... -- scene res://scenes/world_map.tscn /tmp/map 2
## (no class_name references here: see playtest.gd)

var _main: Node
var _t := 0.0
var _wait := 6.0
var _out := "/tmp/shot"
var _stage := 0

func _initialize() -> void:
	# after the Game autoload has loaded the saved settings
	_setup.call_deferred()

func _setup() -> void:
	var a := OS.get_cmdline_user_args()
	var game := root.get_node("Game")
	_out = a[2] if a.size() > 2 else _out
	_wait = float(a[3]) if a.size() > 3 else _wait
	if a[0] == "scene":
		change_scene_to_file(a[1])
		_stage = 10
		return
	game.play_mode = a[0]
	if OS.has_environment("PT_SKIN"):
		game.skin = OS.get_environment("PT_SKIN")
	game.bots = 4
	game.party_bots = 4
	if a[0] == "party":
		game.party_id = a[1]
	else:
		game.level_id = a[1]
	change_scene_to_file("res://scenes/main.tscn")

## Saves the next rendered frame (no awaits in _process: a returned
## function state would read as "quit").
func _save(suffix: String, then_quit := false) -> void:
	RenderingServer.frame_post_draw.connect(func():
		root.get_texture().get_image().save_png(_out + suffix + ".png")
		print("saved ", _out + suffix + ".png")
		if then_quit:
			quit(), CONNECT_ONE_SHOT)

func _process(delta: float) -> bool:
	_t += delta
	if _stage == 10:
		if _t > _wait:
			_stage = 11
			_save("", true)
		return false
	if _main == null:
		_main = current_scene
		if _main == null or not "racers" in _main:
			_main = null
		return false
	if _main.player and not _main.player.has_meta("autopilot"):
		_main.player.set_meta("autopilot", true)
		_main.set_physics_process(false)
		var b = load("res://scripts/bot.gd").new()
		b.level = _main.level
		b.mode = {"survival": "survive", "koth": "koth", "brawl": "brawl"}.get(_main.mode, "race")
		_main.player.add_child(b)
	if _stage == 0 and _t > 4.2 + _wait:
		_stage = 1
		_save("_play")
	elif _stage == 1:
		# bird's-eye view of everything
		_main.set_process(false)
		var bb: AABB = _main.level.bounds
		var c := bb.get_center()
		var span := maxf(bb.size.x, bb.size.z)
		_main.cam.global_position = c + Vector3(0, span * 0.75 + 10.0, span * 0.55)
		_main.cam.look_at(c)
		_main.cam.far = 2000.0
		_main.hud.visible = false
		_stage = 2
		_t = 0.0
	elif _stage == 2 and _t > 0.5:
		_stage = 3
		_save("_top", true)
	return false
