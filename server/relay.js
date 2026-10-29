// Nice Crash! online relay: rooms with 4-letter codes, nothing else.
// Same protocol as LocalRelay in scripts/net.gd:
//   text frames  - JSON control: {op: create|join, name, skin, room}
//                  -> {op: joined, id, host, room, peers} / peer_join /
//                     peer_leave / closed / error
//   binary frames - 4-byte little-endian target peer (0 = everyone else)
//                   + payload; forwarded with the sender's id in its place.
// The first one in a room (id 1) is the host; when it leaves the room closes.
// Run: npm install && npm start   (PORT env var, default 8080)
const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const MAX_ROOM = 8;
const rooms = new Map(); // code -> {peers: Map(id -> ws), next, created}

const server = http.createServer((req, res) => {
  // health check (Render pings this; also handy in a browser)
  res.writeHead(200, { "content-type": "text/plain" });
  res.end(`nice crash relay: ${rooms.size} rooms\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 1 << 20 });

function code() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  let c;
  do {
    c = Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
  } while (rooms.has(c));
  return c;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", () => (ws.isAlive = true));
  ws.on("message", (data, isBinary) => {
    if (!isBinary) {
      let m;
      try { m = JSON.parse(data.toString()); } catch { return; }
      if (ws.room) return; // one room per connection
      let room, roomCode;
      if (m.op === "create") {
        roomCode = code();
        room = { peers: new Map(), next: 1, created: Date.now() };
        rooms.set(roomCode, room);
      } else if (m.op === "join") {
        roomCode = String(m.room || "").toUpperCase();
        room = rooms.get(roomCode);
        if (!room) return send(ws, { op: "error", error: `No room ${roomCode}` });
        if (room.peers.size >= MAX_ROOM) return send(ws, { op: "error", error: "Room is full" });
      } else return;
      const id = room.next++;
      ws.room = roomCode;
      ws.id = id;
      ws.info = { name: String(m.name || "?").slice(0, 16), skin: String(m.skin || "egg").slice(0, 16) };
      room.peers.set(id, ws);
      const peers = [...room.peers].map(([pid, p]) => ({ id: pid, ...p.info }));
      send(ws, { op: "joined", id, host: 1, room: roomCode, peers });
      for (const [pid, p] of room.peers) if (pid !== id) send(p, { op: "peer_join", id, ...ws.info });
      return;
    }
    const room = rooms.get(ws.room);
    if (!room || data.length < 4) return;
    const to = data.readUInt32LE(0);
    data.writeUInt32LE(ws.id, 0);
    if (to === 0) {
      for (const [pid, p] of room.peers) if (pid !== ws.id && p.readyState === p.OPEN) p.send(data, { binary: true });
    } else {
      const p = room.peers.get(to);
      if (p && p.readyState === p.OPEN) p.send(data, { binary: true });
    }
  });
  ws.on("close", () => {
    const room = rooms.get(ws.room);
    if (!room) return;
    room.peers.delete(ws.id);
    if (ws.id === 1 || room.peers.size === 0) {
      for (const p of room.peers.values()) {
        send(p, { op: "closed", reason: "The host left" });
        p.close();
      }
      rooms.delete(ws.room);
    } else {
      for (const p of room.peers.values()) send(p, { op: "peer_leave", id: ws.id });
    }
  });
});

// drop dead connections (phones that lost signal)
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 15000);

server.listen(PORT, () => console.log(`relay listening on ${PORT}`));
