extends SceneTree
## Dev tool: plays a level / party game headless with a bot driving YOU too,
## and reports progress, finishes and eliminations.
##   godot --headless --fixed-fps 60 --script tools/playtest.gd -- adventure meadow 4 race 120
##   godot --headless --fixed-fps 60 --script tools/playtest.gd -- party sumo 3 - 60
## args: mode id bots (race|coop|-) seconds
## Note: don't name class_name scripts here (Bot, Level...): they need the
## Game autoload, which doesn't exist yet when this script compiles.

var _main: Node
var _t := 0.0
var _next_report := 0.0
var _limit := 120.0
var _done := false

func _initialize() -> void:
	# after the Game autoload has loaded the saved settings
	_setup.call_deferred()

func _setup() -> void:
	var a := OS.get_cmdline_user_args()
	var game := root.get_node("Game")
	game.play_mode = a[0] if a.size() > 0 else "adventure"
	if OS.has_environment("PT_SKIN"):
		game.skin = OS.get_environment("PT_SKIN")  # e.g. PT_SKIN=banana
	if game.play_mode == "party":
		game.party_id = a[1] if a.size() > 1 else "waffle"
		game.party_bots = int(a[2]) if a.size() > 2 else 3
	else:
		game.level_id = a[1] if a.size() > 1 else "meadow"
		game.bots = int(a[2]) if a.size() > 2 else 4
		game.coop = a.size() > 3 and a[3] == "coop"
	_limit = float(a[4]) if a.size() > 4 else 120.0
	change_scene_to_file("res://scenes/main.tscn")

func _process(delta: float) -> bool:
	if _done:
		return true
	if _main == null:
		_main = current_scene
		if _main == null or not "racers" in _main:
			_main = null
			return false
		print("level built: %d coins, %d racers, mode %s" % [_main.level.coins_total, _main.racers.size(), _main.mode])
		return false
	if _main.player and not _main.player.has_meta("autopilot"):
		# let a bot drive you too (loaded at runtime: class_name scripts that
		# use the Game autoload can't be referenced before it exists)
		_main.player.set_meta("autopilot", true)
		_main.set_physics_process(false)  # stop the touch controls zeroing the input
		var b = load("res://scripts/bot.gd").new()
		b.level = _main.level
		b.mode = {"survival": "survive", "koth": "koth", "brawl": "brawl"}.get(_main.mode, "quest")
		b.skill = 1.0
		_main.player.add_child(b)
	if not _main.running and not _main._over:
		return false
	_t += delta
	if _t >= _next_report or _main._over:
		_next_report += float(OS.get_environment("PT_EVERY")) if OS.has_environment("PT_EVERY") else 10.0
		var line := "t=%5.1f" % _t
		for p in _main.racers:
			line += "  %s:%s hp%d" % [p.display_name.left(6), "OUT " if p.is_out else "", p.hp]
			if OS.has_environment("PT_POS"):
				line += "(%.0f,%.0f,%.0f)" % [p.global_position.x, p.global_position.y, p.global_position.z]
		if _main.world:
			line += "  missions " + ", ".join(_main.world.missions.map(func(m): return "%d/%d" % [m.got, m.need]))
		print(line)
	if _main._over:
		print("OVER at %.1f s  coins %d/%d  crashes %d  kos %d" % [_t, _main.coins, _main.level.coins_total, _main.crashes, _main.kos])
		var sc := ""
		for p in _main.racers:
			sc += "%s=%.0f " % [p.display_name.left(6), _main._score[p]]
		print("scores: ", sc)
		_done = true
		quit()
	elif _t > _limit:
		print("TIME LIMIT at %.1f s" % _t)
		_done = true
		quit()
	return false
