extends Control
## Play with friends. First: your name, then HOST or JOIN, online (through
## the relay server, a 4-letter room code) or on the same Wi-Fi (the host's
## phone is the server; nearby games show up in a list). Then the room:
## everybody's character on a little stage, and the host picks what to play:
##   PARTY - N rounds of random minigames with a leaderboard (+ bots)
##   WORLD - an open-world zone together, missions shared (+ bot buddies)
## START sends everyone into the game (main.gd).

var _sv: SubViewport
var _world: Node3D
var _cam: Camera3D
var _stage: Node3D
var _figures := {}  # peer id -> Player
var _t := 0.0

var _panel: Control       # current card (connect / room)
var _status: Label
var _lan_box: VBoxContainer
var _name_field: LineEdit
var _code_field: LineEdit
var _ip_field: LineEdit
var _busy := false

# room settings (host)
var _mode := "party"
var _rounds := 5
var _bots := 0
var _zone := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_world()
	Net.connected.connect(_on_connected)
	Net.room_changed.connect(_refresh_room)
	Net.message.connect(_on_message)
	Net.closed.connect(_on_closed)
	Net.lan_found.connect(_refresh_lan)
	var back := UI.round_button("home", UI.CORAL, 84, _leave)
	back.position = Vector2(20, 36)
	add_child(back)
	if Net.in_room:
		_room_card()
	else:
		_connect_card()

func _exit_tree() -> void:
	Net.stop_lan_search()

# ------------------------------------------------------------- 3D stage

func _build_world() -> void:
	_sv = UI.world_view(self)
	_world = Node3D.new()
	_sv.add_child(_world)
	var scenery := Scenery.new()
	scenery.area = AABB(Vector3(-5, 0, -3), Vector3(10, 3, 6))
	scenery.clearance = 18.0
	scenery.theme = "village"
	_world.add_child(scenery)
	var stage := Props.make("models/platform-grass-large-round")
	stage.scale = Vector3(1.6, 0.9, 1.0)
	_world.add_child(stage)
	_stage = Node3D.new()
	_stage.position.y = Props.base_size("models/platform-grass-large-round").y * 0.9
	_world.add_child(_stage)
	for i in 4:
		var f := Props.sized(["nature/flower_redA", "nature/flower_yellowA", "nature/grass_large", "nature/plant_bush"][i], 0.5)
		f.position = Vector3(-3.4 + i * 2.3, _stage.position.y, 1.8)
		_world.add_child(f)
	_cam = Camera3D.new()
	_cam.fov = 40
	_world.add_child(_cam)
	_cam.position = Vector3(0, _stage.position.y + 2.6, 10.5)
	_cam.look_at(Vector3(0, _stage.position.y + 0.2, 0))

func _refresh_figures() -> void:
	var ids := Net.peers.keys() if Net.in_room else [0]
	ids.sort()
	for k in _figures.keys():
		if not k in ids:
			_figures[k].queue_free()
			_figures.erase(k)
	for i in ids.size():
		var id: int = ids[i]
		var skin: String = Game.skin if id == 0 or id == Net.my_id else str(Net.peers[id].get("skin", "egg"))
		var name_: String = Game.player_name if id == 0 or id == Net.my_id else str(Net.peers[id].get("name", "?"))
		var f: Player = _figures.get(id)
		if f and (f.skin != skin or f.display_name != name_):
			f.queue_free()
			f = null
		if f == null:
			f = Player.new()
			f.skin = skin
			f.display_name = name_
			f.freeze = true
			_stage.add_child(f)
			f.set_physics_process(false)
			f.add_name_tag(UI.YELLOW if id == Net.my_id or id == 0 else UI.WHITE)
			_figures[id] = f
		var spread := minf(1.6, 7.0 / maxf(ids.size(), 1))
		f.position = Vector3((i - (ids.size() - 1) * 0.5) * spread, 0.6, 0)

func _process(delta: float) -> void:
	_t += delta
	var i := 0
	for id in _figures:
		var f: Player = _figures[id]
		f.rotation.y = PI + sin(_t * 1.3 + i) * 0.4
		f.visual.position.y = absf(sin(_t * 3.0 + i * 0.7)) * 0.1
		i += 1

# ------------------------------------------------------------- cards

func _card(title: String, color: Color) -> VBoxContainer:
	if _panel:
		_panel.queue_free()
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.offset_bottom = -30
	vb.add_theme_constant_override("separation", -26)
	add_child(vb)
	_panel = vb
	var ribbon := UI.plate(title, color, 44)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ribbon.z_index = 1
	vb.add_child(ribbon)
	var card := PanelContainer.new()
	var st := ChunkyStyle.new(UI.CREAM, 36, 12, false, Vector2(26, 18))
	st.content_margin_top = 44
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size.x = 660
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)
	return inner

func _row(children: Array) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	for c in children:
		hb.add_child(c)
	return hb

func _connect_card() -> void:
	_refresh_figures()
	var vb := _card("PLAY WITH FRIENDS", UI.TEAL)
	_name_field = UI.field(Game.player_name, "Your name", 30, 14, 400)
	_name_field.text_changed.connect(func(t):
		Game.player_name = t.strip_edges() if t.strip_edges() != "" else "Chef"
		Game.save_settings()
		_refresh_figures())
	vb.add_child(_row([UI.label("NAME", 28, UI.INK, false), _name_field]))
	vb.add_child(UI.label("ONLINE (anywhere)", 28, UI.GRAPE))
	_code_field = UI.field("", "CODE", 34, 4, 180)
	_code_field.text_changed.connect(func(t):
		var c := _code_field.caret_column
		_code_field.text = t.to_upper()
		_code_field.caret_column = c)
	vb.add_child(_row([UI.button("HOST", UI.YELLOW, 32, func(): _go(func(): Net.host_room(false)), "online"),
		_code_field, UI.button("JOIN", UI.TEAL, 32, func(): _go(func(): Net.join_room(_code_field.text)), "play")]))
	vb.add_child(UI.label("SAME WI-FI", 28, UI.GRAPE))
	vb.add_child(_row([UI.button("HOST ON WI-FI", UI.YELLOW, 30, func(): _go(func(): Net.host_room(true)), "wifi")]))
	_lan_box = VBoxContainer.new()
	_lan_box.add_theme_constant_override("separation", 8)
	vb.add_child(_lan_box)
	_ip_field = UI.field("", "host IP (if not listed)", 24, 15, 330)
	vb.add_child(_row([_ip_field, UI.button("JOIN", UI.TEAL, 28, func():
		_go(func(): Net.join_room("LAN", _ip_field.text.strip_edges())), "play")]))
	_status = UI.ink_text("", 22)
	vb.add_child(_status)
	Net.start_lan_search()
	_refresh_lan()

func _refresh_lan() -> void:
	if _lan_box == null or not is_instance_valid(_lan_box):
		return
	for c in _lan_box.get_children():
		c.queue_free()
	if Net.lan_games.is_empty():
		_lan_box.add_child(UI.ink_text("Looking for games on this Wi-Fi...", 22))
		return
	for ip in Net.lan_games:
		var g: Dictionary = Net.lan_games[ip]
		var b := UI.button("JOIN %s  (%d)" % [str(g.host).to_upper(), g.players], UI.TEAL, 28, func():
			_go(func(): Net.join_room(g.room, ip)), "play")
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_lan_box.add_child(b)

func _go(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Connecting... (a sleeping server can take up to a minute to wake up)" if Net.kind == "online" else "Connecting..."
	action.call()

func _on_connected(ok: bool, error: String) -> void:
	_busy = false
	if ok:
		Net.stop_lan_search()
		_room_card()
	elif _status and is_instance_valid(_status):
		_status.text = error

func _room_card() -> void:
	_lan_box = null
	var host := Net.is_host()
	var vb := _card("ROOM  %s" % Net.room if Net.kind == "online" else "WI-FI ROOM", UI.YELLOW)
	if Net.kind == "lan" and host:
		vb.add_child(UI.ink_text("Friends on this Wi-Fi: tap JOIN on your game, or type %s" % Net.local_ip(), 22))
	elif Net.kind == "online":
		vb.add_child(UI.ink_text("Friends type the code %s and tap JOIN" % Net.room, 24))
	# skin picker
	var skins := Player.SKINS.keys()
	var skin_plate := UI.plate(Player.SKINS[Game.skin].name, UI.GRAPE, 30)
	skin_plate.custom_minimum_size.x = 220
	var change := func(d: int):
		var i := wrapi(skins.find(Game.skin) + d, 0, skins.size())
		Game.skin = skins[i]
		Game.save_settings()
		UI.plate_label(skin_plate).text = Player.SKINS[Game.skin].name
		Net.update_me()
		_refresh_figures()
	vb.add_child(_row([UI.round_button("left", UI.WHITE, 64, change.bind(-1)), skin_plate, UI.round_button("right", UI.WHITE, 64, change.bind(1))]))
	if host:
		var mode_row := _row([])
		var party_b := UI.button("PARTY", UI.CORAL if _mode == "party" else Color("8a8299"), 32, func():
			_mode = "party"
			_room_card(), "party")
		var world_b := UI.button("WORLD", UI.TEAL if _mode == "world" else Color("8a8299"), 32, func():
			_mode = "world"
			_room_card(), "map")
		mode_row.add_child(party_b)
		mode_row.add_child(world_b)
		vb.add_child(mode_row)
		if _mode == "party":
			vb.add_child(UI.stepper("trophy", _rounds, 1, 10, func(v): _rounds = v, "%d ROUNDS"))
			vb.add_child(UI.stepper("bot", _bots, 0, 4, func(v): _bots = v, "%d BOTS"))
		else:
			var zones := mini(Game.unlocked, Adventure.LEVELS.size() - 1) + 1
			_zone = clampi(_zone, 0, zones - 1)
			var zp := UI.plate(Adventure.LEVELS[_zone].name, Adventure.LEVELS[_zone].color, 28)
			zp.custom_minimum_size.x = 340
			var step := func(d: int):
				_zone = wrapi(_zone + d, 0, zones)
				UI.plate_label(zp).text = Adventure.LEVELS[_zone].name
			vb.add_child(_row([UI.round_button("left", UI.WHITE, 64, step.bind(-1)), zp, UI.round_button("right", UI.WHITE, 64, step.bind(1))]))
			vb.add_child(UI.stepper("bot", _bots, 0, 4, func(v): _bots = v, "%d BUDDIES"))
		var start := UI.button("START", UI.YELLOW, 52, _start, "play", Vector2(340, 0))
		start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(start)
	else:
		vb.add_child(UI.ink_text("Waiting for the host to start...", 26))
	_status = UI.ink_text("%d in the room" % Net.peers.size(), 22)
	vb.add_child(_status)
	_refresh_figures()

func _refresh_room() -> void:
	if not Net.in_room:
		return
	_refresh_figures()
	if _status and is_instance_valid(_status):
		_status.text = "%d in the room" % Net.peers.size()

func _start() -> void:
	var roster := []
	var ids := Net.peers.keys()
	ids.sort()
	var taken := []
	for id in ids:
		roster.append({"peer": id, "name": str(Net.peers[id].name), "skin": str(Net.peers[id].skin)})
		taken.append(str(Net.peers[id].name))
	var bots := []
	var names := ["Eggward", "Sir Toasty", "Donutella", "Burgerella", "Cuppy Cake", "Yolko Ono", "Crumbs", "Sprinkles"]
	names.shuffle()
	var skins := Player.SKINS.keys()
	for i in mini(_bots, 8 - roster.size()):
		bots.append({"name": names[i], "skin": skins[randi() % skins.size()]})
	var g := {"mode": "adventure" if _mode == "world" else "party", "roster": roster, "bots": bots,
		"round": 1, "rounds": _rounds if _mode == "party" else 1, "totals": {}, "played": []}
	g.id = Adventure.LEVELS[_zone].id if _mode == "world" else Party.GAMES.keys().pick_random()
	Net.to_all("start", g)

func _on_message(_from: int, type: String, data) -> void:
	if type == "start" and data is Dictionary:
		Net.game = data
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_closed(reason: String) -> void:
	_connect_card()
	_status.text = reason

func _leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
