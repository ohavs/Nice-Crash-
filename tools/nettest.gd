extends SceneTree
## Dev tool: a networked game between headless copies, bots driving.
##   node server/relay.js &      (or use "lan": the host runs the relay itself)
##   godot --headless --script tools/nettest.gd -- host online|lan party|world <id> <secs> <codefile> [players] [bots]
##   godot --headless --script tools/nettest.gd -- join online|lan - - <secs> <codefile>
## The host writes the room code to <codefile>, joiners read it. Prints the
## room, who's in the game, positions, scores and how the round ended.
## (no class_name references here: see playtest.gd)

var _net: Node
var _game: Node
var _role := "host"
var _args: PackedStringArray
var _limit := 60.0
var _t := 0.0
var _main: Node
var _next := 0.0
var _started := false

func _initialize() -> void:
	_setup.call_deferred()

func _setup() -> void:
	Engine.max_fps = 60  # real time: both copies must keep pace with each other
	_args = OS.get_cmdline_user_args()
	_role = _args[0]
	_limit = float(_args[4])
	_net = root.get_node("Net")
	_game = root.get_node("Game")
	_game.relay_url = "ws://127.0.0.1:8080"
	_game.player_name = _role.to_upper() + str(randi() % 100)
	_net.connected.connect(func(ok, err): print(_role, " connected ", ok, " ", err, " room ", _net.room, " id ", _net.my_id))
	_net.message.connect(_on_msg)
	_net.closed.connect(func(r): print(_role, " CLOSED ", r))
	var lan: bool = _args[1] == "lan"
	if _role == "host":
		_net.host_room(lan)
	else:
		var code := ""
		for i in 100:
			if FileAccess.file_exists(_args[5]):
				code = FileAccess.get_file_as_string(_args[5]).strip_edges()
				if code != "":
					break
			OS.delay_msec(200)
		_net.join_room(code if not lan else "LAN", "127.0.0.1" if lan else "")

func _on_msg(_from: int, type: String, data) -> void:
	if type == "start":
		_net.game = data
		print(_role, " START ", data.mode, " ", data.id, " roster ", data.roster.size(), " bots ", data.bots.size())
		change_scene_to_file("res://scenes/main.tscn")
	elif type == "end":
		print(_role, " END order ", data.order, " totals ", data.totals)
		if _role == "host" and _main and int(_net.game.get("round", 1)) < int(_net.game.get("rounds", 1)):
			create_timer(2.0).timeout.connect(func(): _main._net_next_round())
	elif type == "next":
		print(_role, " NEXT ROUND ", data.round, " ", data.id)
	elif type == "lobby":
		print(_role, " back to lobby")

func _process(delta: float) -> bool:
	_t += delta
	if _role == "host" and _net.in_room and not _started:
		var f := FileAccess.open(_args[5], FileAccess.WRITE)
		f.store_string(_net.room)
		f.close()
		var want := int(_args[6]) if _args.size() > 6 else 2
		if _net.peers.size() >= want:
			_started = true
			var roster := []
			for id in _net.peers:
				roster.append({"peer": id, "name": _net.peers[id].name, "skin": _net.peers[id].skin})
			var bots := []
			for i in (int(_args[7]) if _args.size() > 7 else 1):
				bots.append({"name": "Bot%d" % i, "skin": "toast"})
			var mode: String = "adventure" if _args[2] == "world" else "party"
			_net.to_all("start", {"mode": mode, "id": _args[3], "roster": roster, "bots": bots,
				"round": 1, "rounds": 2, "totals": {}, "played": []})
	if current_scene and "racers" in current_scene and current_scene != _main:
		_main = current_scene
		_next = _t + 3.0
	if _main and is_instance_valid(_main) and _main.player and not _main.player.has_meta("autopilot"):
		_main.player.set_meta("autopilot", true)
		_main.set_physics_process(false)
		var b = load("res://scripts/bot.gd").new()
		b.level = _main.level
		b.mode = {"survival": "survive", "koth": "koth", "brawl": "brawl"}.get(_main.mode, "quest")
		b.skill = 1.0
		_main.player.add_child(b)
	if _main and is_instance_valid(_main) and OS.has_environment("PT_START") and _main.running and not _main.player.has_meta("moved") and _main.player.is_grounded():
		_main.player.set_meta("moved", true)
		var xz := OS.get_environment("PT_START").split(",")
		_main.player.checkpoint = _main.world.ground(float(xz[0]), float(xz[1]))
		_main.player.respawn(false)
	if _main and is_instance_valid(_main) and _t > _next:
		_next = _t + 3.0
		var line := "%s t=%.0f running=%s" % [_role, _t, _main.running]
		for p in _main.racers:
			if is_instance_valid(p):
				line += "  %s%s(%.0f,%.0f,%.0f)hp%d%s" % [p.display_name.left(6), "*" if p.puppet else "", p.global_position.x, p.global_position.y, p.global_position.z, p.hp, " OUT" if p.is_out else ""]
		if _main.world:
			line += "  missions " + ", ".join(_main.world.missions.map(func(m): return "%d/%d" % [m.got, m.need]))
			var alive := 0
			for e in _main.world.enemies:
				if is_instance_valid(e) and not e.is_dead():
					alive += 1
			line += " enemies %d" % alive
		elif _main.mode in ["koth", "brawl"]:
			line += "  scores " + str(_main._score.values())
		print(line)
	if _t > _limit:
		print(_role, " DONE")
		quit()
	return false
