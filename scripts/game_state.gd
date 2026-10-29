extends Node
## Global state: version, sounds, slow-motion, settings, update check.

const REPO_API := "https://api.github.com/repos/ohavs/nice-crash-/releases/latest"

const SETTINGS_PATH := "user://settings.cfg"
## Touch control centers as fractions of the screen (x, y).
const DEFAULT_LAYOUT := {
	"joy": Vector2(0.72, 0.82),
	"jump": Vector2(0.19, 0.84),
	"grab": Vector2(0.42, 0.92),
}

var sounds := {}
var skin := "egg"
var layout := DEFAULT_LAYOUT.duplicate()
var _slowmo_left := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for s in ["jump", "land", "fall", "break", "coin", "walking"]:
		sounds[s] = load("res://assets/kenney/sounds/%s.ogg" % s)

func build() -> int:
	return int(ProjectSettings.get_setting("application/config/build", 0))

func version_text() -> String:
	return "v%s (build %d)" % [ProjectSettings.get_setting("application/config/version"), build()]

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	skin = cfg.get_value("game", "skin", skin)
	for k in DEFAULT_LAYOUT:
		var v = cfg.get_value("controls", k, DEFAULT_LAYOUT[k])
		if v is Vector2:
			layout[k] = v.clamp(Vector2.ZERO, Vector2.ONE)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "skin", skin)
	for k in layout:
		cfg.set_value("controls", k, layout[k])
	cfg.save(SETTINGS_PATH)

func reset_layout() -> void:
	layout = DEFAULT_LAYOUT.duplicate()
	save_settings()

func play(name: String, pitch_jitter := 0.15, volume_db := 0.0) -> void:
	if not sounds.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sounds[name]
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.volume_db = volume_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func slowmo(scale: float, real_seconds: float) -> void:
	Engine.time_scale = scale
	_slowmo_left = real_seconds

func _process(delta: float) -> void:
	if _slowmo_left > 0.0:
		# delta is scaled; convert back to real time
		_slowmo_left -= delta / max(Engine.time_scale, 0.01)
		if _slowmo_left <= 0.0:
			Engine.time_scale = 1.0

# --- Update check (GitHub Releases) -------------------------------------

signal update_checked(available: bool, latest_build: int, url: String, error: String)

func check_for_updates() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			update_checked.emit(false, 0, "", "No connection (%d)" % code)
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			update_checked.emit(false, 0, "", "Bad response")
			return
		var tag: String = str(data.get("tag_name", "")).trim_prefix("v")
		var latest := int(tag.get_slice(".", tag.get_slice_count(".") - 1)) if tag.contains(".") else int(tag)
		var url := ""
		for a in data.get("assets", []):
			if str(a.get("name", "")).ends_with(".apk"):
				url = a.get("browser_download_url", "")
		update_checked.emit(latest > build() and url != "", latest, url, ""))
	var err := http.request(REPO_API, ["User-Agent: NiceCrash"])
	if err != OK:
		http.queue_free()
		update_checked.emit(false, 0, "", "Request failed")
