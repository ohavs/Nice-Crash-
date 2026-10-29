extends SceneTree
## Dev tool: close-up lineup of every playable skin standing on a floor
## (with limbs and faces), front view, to check how the characters read.
##   xvfb-run -a godot --rendering-method mobile --resolution 1280x720 --script tools/char_sheet.gd -- /tmp/chars.png [secs] [crash]
## `crash` knocks everyone over after a moment (crash faces / cracks).
## (no class_name references here: see playtest.gd)

var _out := "/tmp/chars.png"
var _wait := 1.5
var _t := 0.0
var _done := false
var _players: Array = []
var _crash := false

func _initialize() -> void:
	_setup.call_deferred()

func _setup() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else _out
	_wait = float(a[1]) if a.size() > 1 else _wait
	_crash = a.size() > 2 and a[2] == "crash"
	var w := Node3D.new()
	root.add_child(w)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color("9fc7e8")
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color.WHITE
	we.environment.ambient_light_energy = 0.55
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	floor.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("7fa86a")
	mi.material_override = fm
	floor.add_child(mi)
	floor.position.y = -0.5
	w.add_child(floor)
	var skins: Array = load("res://scripts/player.gd").SKINS.keys()
	for i in skins.size():
		var p: RigidBody3D = load("res://scripts/player.gd").new()
		p.skin = skins[i]
		w.add_child(p)
		p.global_position = Vector3((i - (skins.size() - 1) * 0.5) * 1.6, 0.7, 0)
		p.set("_face_dir", Vector3.BACK)
		p.rotation.y = PI
		_players.append(p)
	var cam := Camera3D.new()
	cam.fov = 40
	w.add_child(cam)
	cam.position = Vector3(0, 1.6, 7.5)
	cam.look_at(Vector3(0, 0.5, 0))

func _process(delta: float) -> bool:
	_t += delta
	if _crash and _t > 0.6 and _t - delta <= 0.6:
		for p in _players:
			p.call("hit", Vector3(0, 4, 1.5))
	if not _done and _t > _wait:
		_done = true
		RenderingServer.frame_post_draw.connect(func():
			root.get_texture().get_image().save_png(_out)
			print("saved ", _out)
			quit(), CONNECT_ONE_SHOT)
	return false
