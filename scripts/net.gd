extends Node
## Multiplayer (autoload "Net"): rooms with a 4-letter code, through a relay.
##   ONLINE    - connects to the relay server (server/relay.js, its address is
##               Game.relay_url) over WebSocket; anyone anywhere can join.
##   SAME WI-FI - the host's phone runs the same relay itself (LocalRelay
##               below) and announces the room on the local network (UDP
##               broadcast); the others find it in the list, or type the
##               host's IP.
## Everybody, the host included, is a plain client of the relay. Messages:
##   relay control (JSON text): create / join / joined / peer_join /
##     peer_leave / closed / error
##   game data (binary): 4-byte target peer (0 = everyone else) + payload;
##     the relay swaps the target for the sender's id when forwarding.
## Payloads are var_to_bytes([type, data]). The host (peer 1) is the
## authority for rounds, scores, enemies and missions; every peer owns its
## own player and streams it (see main.gd).

signal connected(ok: bool, error: String)
signal room_changed
signal message(from: int, type: String, data)
signal closed(reason: String)
signal lan_found

const LAN_PORT := 24680
const BEACON_PORT := 24681

## In a room right now.
var in_room := false
var my_id := 0
var host_id := 1
var room := ""
## peer id -> {name, skin}
var peers := {}
## "online" | "lan"
var kind := "online"
## Set while a networked game is being played (main.gd reads it).
var game := {}
## LAN games heard on the network: ip -> {room, host, port, seen}
var lan_games := {}

var _ws: WebSocketPeer
var _pending_op := {}
var _relay: LocalRelay
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _beacon_t := 0.0
var _state := ""  # "" | connecting | open

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func active() -> bool:
	return in_room and not game.is_empty()

func is_host() -> bool:
	return in_room and my_id == host_id

func is_client() -> bool:
	return active() and my_id != host_id

# ---------------------------------------------------------------- rooms

## Make a room. lan = host it on this phone for the same Wi-Fi.
func host_room(lan: bool) -> void:
	kind = "lan" if lan else "online"
	if lan:
		_relay = LocalRelay.new()
		var err := _relay.start(LAN_PORT)
		if err != OK:
			_relay = null
			connected.emit(false, "Can't open port %d (%s)" % [LAN_PORT, error_string(err)])
			return
		add_child(_relay)
		_open("ws://127.0.0.1:%d" % LAN_PORT, {"op": "create"})
	else:
		_open(Game.relay_url, {"op": "create"})

## Join a room by code (online) or a LAN host's address.
func join_room(code: String, lan_ip := "") -> void:
	kind = "lan" if lan_ip != "" else "online"
	var url := "ws://%s:%d" % [lan_ip, LAN_PORT] if lan_ip != "" else Game.relay_url
	_open(url, {"op": "join", "room": code.to_upper()})

func leave() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_state = ""
	_stop_lan()
	in_room = false
	game = {}
	peers.clear()
	room = ""
	my_id = 0

func _open(url: String, op: Dictionary) -> void:
	leave_socket_only()
	if url == "":
		connected.emit(false, "No online server set up yet (see Settings)")
		return
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		connected.emit(false, "Can't connect (%s)" % error_string(err))
		return
	op["name"] = Game.player_name
	op["skin"] = Game.skin
	op["v"] = Game.build()
	_pending_op = op
	_state = "connecting"
	_connect_t = 0.0

var _connect_t := 0.0

func leave_socket_only() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_state = ""

## Tell the others our skin/name changed (lobby).
func update_me() -> void:
	if not in_room:
		return
	peers[my_id] = {"name": Game.player_name, "skin": Game.skin}
	send(0, "me", peers[my_id])
	room_changed.emit()

# ---------------------------------------------------------------- send

func send(to: int, type: String, data = null) -> void:
	if _ws == null or _state != "open":
		return
	var payload := var_to_bytes([type, data])
	var buf := PackedByteArray()
	buf.resize(4)
	buf.encode_u32(0, to)
	buf.append_array(payload)
	_ws.put_packet(buf)

func to_host(type: String, data = null) -> void:
	if is_host():
		message.emit(my_id, type, data)
	else:
		send(host_id, type, data)

## Everyone, including ourselves (host broadcasts that the host also acts on).
func to_all(type: String, data = null) -> void:
	send(0, type, data)
	message.emit(my_id, type, data)

## Owner peer of a player's net id ("<peer>:<slot>").
static func owner_of(net_id: String) -> int:
	return int(net_id.get_slice(":", 0))

func send_hit(p: Player, impulse: Vector3, by: Player) -> void:
	if not active():
		return
	send(owner_of(p.net_id), "hit", [p.net_id, impulse, by.net_id if by else ""])

func send_push(p: Player, impulse: Vector3, by: Player) -> void:
	if not active():
		return
	send(owner_of(p.net_id), "push", [p.net_id, impulse, by.net_id if by else ""])

func send_enemy_hit(eid: int, dmg: int, dir: Vector3, by: Player) -> void:
	if not active():
		return
	to_host("ehit", [eid, dmg, dir, by.net_id if by else ""])

## Open world pickups / switches done here: tell the others.
func world_event(type: String, args: Array) -> void:
	if active():
		send(0, "w_" + type, args)

## Something fired (thrown items, cannonballs, rollers, skeleton shots):
## everyone spawns a copy, hits only count on the target's owner.
func fire(kind_: String, pos: Vector3, vel: Vector3, by: String) -> void:
	if active():
		send(0, "fire", [kind_, pos, vel, by])

# ---------------------------------------------------------------- LAN discovery

func start_lan_search() -> void:
	if _listen:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(BEACON_PORT) != OK:
		_listen = null

func stop_lan_search() -> void:
	if _listen:
		_listen.close()
	_listen = null
	lan_games.clear()

func _stop_lan() -> void:
	if _relay:
		_relay.stop()
		_relay.queue_free()
	_relay = null
	if _beacon:
		_beacon.close()
	_beacon = null

## This phone's address on the Wi-Fi (for "join by IP").
static func local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return ""

func _beacon_tick(delta: float) -> void:
	_beacon_t -= delta
	if _beacon_t > 0.0:
		return
	_beacon_t = 1.0
	if _beacon == null:
		_beacon = PacketPeerUDP.new()
		_beacon.set_broadcast_enabled(true)
		_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	var msg := "NICECRASH|%s|%s|%d|%d" % [room, Game.player_name, LAN_PORT, peers.size()]
	_beacon.put_packet(msg.to_utf8_buffer())

func _listen_tick() -> void:
	var now := Time.get_ticks_msec()
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet().get_string_from_utf8()
		var ip := _listen.get_packet_ip()
		var parts := pkt.split("|")
		if parts.size() >= 5 and parts[0] == "NICECRASH":
			if not lan_games.has(ip):
				changed = true
			lan_games[ip] = {"room": parts[1], "host": parts[2], "port": int(parts[3]), "players": int(parts[4]), "seen": now}
	for ip in lan_games.keys():
		if now - lan_games[ip].seen > 4000:
			lan_games.erase(ip)
			changed = true
	if changed:
		lan_found.emit()

# ---------------------------------------------------------------- poll

func _process(delta: float) -> void:
	if _listen:
		_listen_tick()
	if _relay and in_room:
		_beacon_tick(delta)
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if _state == "connecting":
		_connect_t += delta
		if st == WebSocketPeer.STATE_OPEN:
			_state = "open"
			_ws.send_text(JSON.stringify(_pending_op))
		elif st == WebSocketPeer.STATE_CLOSED or _connect_t > 75.0:
			_ws = null
			_state = ""
			_stop_lan()
			connected.emit(false, "Server unreachable")
		return
	if st == WebSocketPeer.STATE_CLOSED:
		var was := in_room
		_ws = null
		_state = ""
		_stop_lan()
		in_room = false
		game = {}
		if was:
			closed.emit("Connection lost")
		return
	while _ws and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_control(JSON.parse_string(pkt.get_string_from_utf8()))
		elif pkt.size() >= 4:
			var from := pkt.decode_u32(0)
			var v = bytes_to_var(pkt.slice(4))
			if v is Array and v.size() == 2:
				if v[0] == "me" and v[1] is Dictionary:
					peers[from] = v[1]
					room_changed.emit()
				message.emit(from, v[0], v[1])

func _control(m) -> void:
	if not m is Dictionary:
		return
	match str(m.get("op", "")):
		"joined":
			in_room = true
			my_id = int(m.id)
			host_id = int(m.get("host", 1))
			room = str(m.room)
			peers.clear()
			for p in m.get("peers", []):
				peers[int(p.id)] = {"name": str(p.name), "skin": str(p.skin)}
			connected.emit(true, "")
			room_changed.emit()
		"peer_join":
			peers[int(m.id)] = {"name": str(m.name), "skin": str(m.skin)}
			room_changed.emit()
			message.emit(int(m.id), "peer_join", null)
		"peer_leave":
			peers.erase(int(m.id))
			room_changed.emit()
			message.emit(int(m.id), "peer_leave", null)
		"closed":
			var was := in_room
			leave()
			if was:
				closed.emit(str(m.get("reason", "The host left")))
		"error":
			var e := str(m.get("error", "Error"))
			leave()
			connected.emit(false, e)


## The relay, run on the host's phone for same-Wi-Fi games. Same protocol
## as server/relay.js, one room.
class LocalRelay extends Node:
	var _server := TCPServer.new()
	var _socks := {}  # id -> WebSocketPeer
	var _info := {}   # id -> {name, skin}
	var _pending: Array = []
	var _next := 1
	var _code := ""

	func start(port: int) -> Error:
		var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ"
		for i in 4:
			_code += chars[randi() % chars.length()]
		return _server.listen(port)

	func stop() -> void:
		for id in _socks:
			_socks[id].close()
		_socks.clear()
		_server.stop()

	func _process(_delta: float) -> void:
		while _server.is_connection_available():
			var ws := WebSocketPeer.new()
			ws.inbound_buffer_size = 1 << 20
			ws.outbound_buffer_size = 1 << 20
			ws.accept_stream(_server.take_connection())
			_pending.append(ws)
		for ws: WebSocketPeer in _pending.duplicate():
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				_pending.erase(ws)
			elif ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
				var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				_pending.erase(ws)
				if not m is Dictionary:
					ws.close()
					continue
				if m.get("op") == "join" and str(m.get("room", "")) != _code:
					ws.send_text(JSON.stringify({"op": "error", "error": "No room " + str(m.get("room", ""))}))
					continue
				var id := _next
				_next += 1
				var peers := []
				for o in _info:
					peers.append({"id": o, "name": _info[o].name, "skin": _info[o].skin})
				_info[id] = {"name": str(m.get("name", "?")), "skin": str(m.get("skin", "egg"))}
				peers.append({"id": id, "name": _info[id].name, "skin": _info[id].skin})
				_socks[id] = ws
				ws.send_text(JSON.stringify({"op": "joined", "id": id, "host": 1, "room": _code, "peers": peers}))
				for o in _socks:
					if o != id:
						_socks[o].send_text(JSON.stringify({"op": "peer_join", "id": id, "name": _info[id].name, "skin": _info[id].skin}))
		for id in _socks.keys():
			var ws: WebSocketPeer = _socks[id]
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				_socks.erase(id)
				_info.erase(id)
				for o in _socks:
					if id == 1:
						_socks[o].send_text(JSON.stringify({"op": "closed", "reason": "The host left"}))
					else:
						_socks[o].send_text(JSON.stringify({"op": "peer_leave", "id": id}))
				continue
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				if ws.was_string_packet() or pkt.size() < 4:
					continue
				var to := pkt.decode_u32(0)
				pkt.encode_u32(0, id)
				if to == 0:
					for o in _socks:
						if o != id:
							_socks[o].put_packet(pkt)
				elif _socks.has(to):
					_socks[to].put_packet(pkt)
