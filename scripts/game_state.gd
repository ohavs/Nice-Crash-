extends Node
## Global state: version, sounds, slow-motion, settings, update check.

const REPO_API := "https://api.github.com/repos/ohavs/nice-crash-/releases/latest"

const SETTINGS_PATH := "user://settings.cfg"
## Online multiplayer relay (server/relay.js deployed somewhere, wss://...).
## Can be changed in Settings -> Online server.
const DEFAULT_RELAY := ""
## Touch control centers as fractions of the screen (x, y).
const DEFAULT_LAYOUT := {
	"joy": Vector2(0.72, 0.82),
	"jump": Vector2(0.19, 0.84),
	"grab": Vector2(0.42, 0.92),
	"act": Vector2(0.40, 0.74),
}

var sounds := {}
var skin := "egg"
var layout := DEFAULT_LAYOUT.duplicate()
## Touch control size multipliers (SIZE_MIN..SIZE_MAX), same keys as layout.
const SIZE_MIN := 0.7
const SIZE_MAX := 1.4
var sizes := {"joy": 1.0, "jump": 1.0, "grab": 1.0, "act": 1.0}
## "adventure" (world levels) or "party" (minigames).
var play_mode := "adventure"
var level_id := "meadow"
var party_id := "waffle"
## Bots in adventure (0-4) and whether they're on your team.
var bots := 2
var coop := false
## Opponents in party games (1-4).
var party_bots := 3
## Party show: how many rounds (1 = a single game).
var party_rounds := 1
## The party show in progress: {rounds, round, totals: key -> points,
## names: key -> name, played: [game ids]}; empty = none.
var show := {}
## Your name in multiplayer lobbies.
var player_name := ""
var relay_url := DEFAULT_RELAY
## Menu should reopen the party game list (coming back from a party game).
var open_party := false
## Adventure progress: highest unlocked level index, best stars per level.
var unlocked := 0
var stars := {}
var _slowmo_left := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	if player_name == "":
		player_name = ["Chef", "Snacky", "Crumb", "Nibbles", "Muffin", "Pickle"].pick_random() + str(randi_range(10, 99))
		save_settings()
	for s in ["jump", "land", "fall", "break", "coin", "walking"]:
		sounds[s] = load("res://assets/kenney/sounds/%s.ogg" % s)
	for f in DirAccess.get_files_at("res://assets/kenney/sfx"):
		# exported builds list "x.ogg.import" instead of "x.ogg"
		var n := f.trim_suffix(".import")
		if n.ends_with(".ogg") and not sounds.has(n.get_basename()):
			sounds[n.get_basename()] = load("res://assets/kenney/sfx/" + n)

func build() -> int:
	return int(ProjectSettings.get_setting("application/config/build", 0))

func version_text() -> String:
	return "v%s (build %d)" % [ProjectSettings.get_setting("application/config/version"), build()]

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	skin = cfg.get_value("game", "skin", skin)
	if not Player.SKINS.has(skin):
		skin = "egg"
	level_id = cfg.get_value("game", "level", level_id)
	party_id = cfg.get_value("game", "party", party_id)
	bots = clampi(int(cfg.get_value("game", "bots", bots)), 0, 4)
	coop = bool(cfg.get_value("game", "coop", coop))
	party_bots = clampi(int(cfg.get_value("game", "party_bots", party_bots)), 1, 4)
	party_rounds = clampi(int(cfg.get_value("game", "party_rounds", party_rounds)), 1, 10)
	player_name = str(cfg.get_value("net", "name", player_name))
	relay_url = str(cfg.get_value("net", "relay", relay_url))
	if relay_url == "":
		relay_url = DEFAULT_RELAY
	unlocked = int(cfg.get_value("progress", "unlocked", unlocked))
	var st = cfg.get_value("progress", "stars", {})
	if st is Dictionary:
		stars = st
	for k in DEFAULT_LAYOUT:
		var v = cfg.get_value("controls", k, DEFAULT_LAYOUT[k])
		if v is Vector2:
			layout[k] = v.clamp(Vector2.ZERO, Vector2.ONE)
		sizes[k] = clampf(float(cfg.get_value("control_sizes", k, 1.0)), SIZE_MIN, SIZE_MAX)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "skin", skin)
	cfg.set_value("game", "level", level_id)
	cfg.set_value("game", "party", party_id)
	cfg.set_value("game", "bots", bots)
	cfg.set_value("game", "coop", coop)
	cfg.set_value("game", "party_bots", party_bots)
	cfg.set_value("game", "party_rounds", party_rounds)
	cfg.set_value("net", "name", player_name)
	cfg.set_value("net", "relay", relay_url)
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "stars", stars)
	for k in layout:
		cfg.set_value("controls", k, layout[k])
		cfg.set_value("control_sizes", k, sizes[k])
	cfg.save(SETTINGS_PATH)

## Records open world progress: best stars (missions done) for a zone; two
## stars open the next zone.
func complete_level(id: String, got_stars: int) -> void:
	stars[id] = maxi(int(stars.get(id, 0)), got_stars)
	if got_stars >= 2:
		unlocked = maxi(unlocked, Adventure.index_of(id) + 1)
	save_settings()

func total_stars() -> int:
	var n := 0
	for l in Adventure.LEVELS:
		n += int(stars.get(l.id, 0))
	return n

func reset_layout() -> void:
	layout = DEFAULT_LAYOUT.duplicate()
	for k in sizes:
		sizes[k] = 1.0
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
