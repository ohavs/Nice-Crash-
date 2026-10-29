# Nice Crash! online relay

A tiny WebSocket relay (`relay.js`, Node 18+, one dependency: `ws`). It only
keeps rooms with 4-letter codes and forwards messages between the phones in
a room; the host's phone runs the game logic. Same protocol as the built-in
Wi-Fi relay (`LocalRelay` in `scripts/net.gd`).

## Run it locally

    cd server && npm install && npm start      # ws://localhost:8080

## Put it online (free, Render.com)

1. Sign up at https://render.com (GitHub login is fine).
2. Dashboard -> **New** -> **Blueprint** -> pick the `Nice-Crash-` repo.
   Render reads `render.yaml` and creates the `nice-crash-relay` web service
   (free plan, `server/` folder, `npm install` / `npm start`).
3. When it's live you get an address like
   `https://nice-crash-relay-xxxx.onrender.com`. The game wants the same
   with `wss://`: `wss://nice-crash-relay-xxxx.onrender.com`.
4. Put that in the game (Settings -> ONLINE SERVER), or make it the default
   for everyone: `DEFAULT_RELAY` in `scripts/game_state.gd`.

The free plan sleeps after ~15 minutes without visitors; the first HOST/JOIN
after that waits up to a minute while it wakes up (the lobby says so).

Any other Node host with WebSockets works the same way (Railway, Fly.io,
a VPS: `PORT=80 node relay.js`).
