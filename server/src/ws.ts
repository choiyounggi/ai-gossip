import { WebSocketServer, type WebSocket } from 'ws';
import * as os from 'node:os';
import type {
  ClientToServer,
  Participant,
  ServerToClient,
} from './protocol.ts';
import { MAX_PARTICIPANTS } from './protocol.ts';
import { RoomManager } from './room.ts';

/** Return LAN-reachable IPv4 addresses (non-internal). */
export function getLanAddresses(): string[] {
  const ifaces = os.networkInterfaces();
  const out: string[] = [];
  for (const name of Object.keys(ifaces)) {
    for (const info of ifaces[name] ?? []) {
      if (info.family === 'IPv4' && !info.internal) {
        out.push(info.address);
      }
    }
  }
  return out;
}

interface Connection {
  ws: WebSocket;
  userId?: string;
  roomId?: string;
  /** Room this socket is *watching* (passive lobby view, not a participant). */
  watchedRoomId?: string;
  /** Set to true on every pong; ping tick flips to false and terminates if still false. */
  isAlive: boolean;
}

export interface StartServerOptions {
  port: number;
}

/**
 * How long a socket can stay dropped before we actually remove the user
 * from the room. Within this window, a JOIN_ROOM with sinceSeq resumes
 * the same participant on a new socket.
 */
const RECONNECT_GRACE_MS = 30_000;

/** Ping cadence; a client has one full cadence to pong before we terminate. */
const HEARTBEAT_MS = 30_000;

export function startServer(opts: StartServerOptions): WebSocketServer {
  const wss = new WebSocketServer({ port: opts.port });
  const connections = new Map<string, Connection>(); // by userId
  /** userId → timer scheduled to finalize leave after grace period expires. */
  const graceTimers = new Map<string, NodeJS.Timeout>();
  /** Lobby watchers grouped by roomId. A single socket shows up here only
   *  while it has not yet sent JOIN_ROOM — on JOIN we drop it from the set. */
  const lobbyWatchers = new Map<string, Set<WebSocket>>();

  const send = (userId: string, msg: ServerToClient): void => {
    const c = connections.get(userId);
    if (!c) return;
    if (c.ws.readyState !== c.ws.OPEN) return;
    c.ws.send(JSON.stringify(msg));
  };

  const broadcastLobbyState = (
    roomId: string,
    participants: Participant[],
    isFull: boolean,
  ): void => {
    const set = lobbyWatchers.get(roomId);
    if (!set || set.size === 0) return;
    const frame = JSON.stringify({
      type: 'LOBBY_STATE',
      roomId,
      participants,
      isFull,
    } satisfies ServerToClient);
    for (const ws of set) {
      if (ws.readyState === ws.OPEN) ws.send(frame);
    }
  };

  const rooms = new RoomManager(send, broadcastLobbyState);

  const sendDirect = (ws: WebSocket, msg: ServerToClient): void => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
  };

  /** Remove grace timer + clean up after a user is fully gone. */
  const finalizeDisconnect = (userId: string, roomId: string): void => {
    const timer = graceTimers.get(userId);
    if (timer) {
      clearTimeout(timer);
      graceTimers.delete(userId);
    }
    const room = rooms.get(roomId);
    room?.finalizeLeave(userId);
    connections.delete(userId);
  };

  wss.on('connection', (ws) => {
    const conn: Connection = { ws, isAlive: true };

    ws.on('pong', () => {
      conn.isAlive = true;
    });

    ws.on('message', (raw) => {
      let parsed: ClientToServer;
      try {
        parsed = JSON.parse(raw.toString()) as ClientToServer;
      } catch {
        ws.send(JSON.stringify({ type: 'ERROR', reason: 'invalid JSON' }));
        return;
      }

      handleMessage(parsed, conn);
    });

    ws.on('close', () => {
      if (conn.userId && conn.roomId) {
        const room = rooms.get(conn.roomId);
        const userId = conn.userId;
        const roomId = conn.roomId;
        // If the socket in the connections map is the same one that just
        // closed, start the grace period. If it's a newer socket (the user
        // already reconnected), leave connections untouched.
        const tracked = connections.get(userId);
        if (tracked?.ws === ws) {
          room?.markDisconnected(userId);
          const timer = setTimeout(() => {
            graceTimers.delete(userId);
            finalizeDisconnect(userId, roomId);
          }, RECONNECT_GRACE_MS);
          graceTimers.set(userId, timer);
        }
      }
      if (conn.watchedRoomId) {
        lobbyWatchers.get(conn.watchedRoomId)?.delete(ws);
      }
    });

    ws.on('error', (err) => {
      console.error('[ws] socket error:', err.message);
    });
  });

  // Heartbeat: ping everyone every HEARTBEAT_MS; any socket that didn't pong
  // since last tick is presumed dead and gets terminated (triggering 'close'
  // which then runs the grace-period flow). Covers half-open TCP (NAT drops,
  // WiFi handoff, laptop sleep-then-wake) that never surfaces a close event.
  const heartbeat = setInterval(() => {
    for (const client of wss.clients) {
      const conn = findConnectionByWs(connections, client);
      if (conn && !conn.isAlive) {
        // Didn't pong since last tick — force close so we hit the grace path.
        client.terminate();
        continue;
      }
      if (conn) conn.isAlive = false;
      try {
        client.ping();
      } catch {
        // Ignore; terminate on next tick if still bad.
      }
    }
  }, HEARTBEAT_MS);

  wss.on('close', () => {
    clearInterval(heartbeat);
    for (const t of graceTimers.values()) clearTimeout(t);
    graceTimers.clear();
  });

  function handleMessage(msg: ClientToServer, conn: Connection): void {
    switch (msg.type) {
      case 'JOIN_ROOM': {
        // Promote this socket from lobby-watcher to full participant.
        if (conn.watchedRoomId) {
          lobbyWatchers.get(conn.watchedRoomId)?.delete(conn.ws);
          conn.watchedRoomId = undefined;
        }

        const room = rooms.getOrCreate(msg.roomId);

        // Reconnect path: this userId already has a participant slot in the
        // room and the client sent a sinceSeq hint. Swap the socket handle
        // and replay missed messages — no roster change, no turn rotation.
        if (
          typeof msg.sinceSeq === 'number' &&
          room.hasParticipant(msg.userId) &&
          !room.isClosed
        ) {
          // Cancel grace timer; we got back in time.
          const timer = graceTimers.get(msg.userId);
          if (timer) {
            clearTimeout(timer);
            graceTimers.delete(msg.userId);
          }

          // Terminate any previous socket we still have on file for this
          // user (shouldn't exist after grace, but defensive).
          const prev = connections.get(msg.userId);
          if (prev && prev.ws !== conn.ws && prev.ws.readyState === prev.ws.OPEN) {
            prev.ws.close(4000, 'resumed on new socket');
          }

          connections.set(msg.userId, {
            ws: conn.ws,
            userId: msg.userId,
            roomId: msg.roomId,
            isAlive: true,
          });
          conn.userId = msg.userId;
          conn.roomId = msg.roomId;

          const result = room.reconnect(msg.userId, msg.sinceSeq);
          if (result.ok) {
            send(msg.userId, {
              type: 'ROOM_SNAPSHOT',
              roomId: msg.roomId,
              history: result.missed,
              participants: result.participants,
            });
          } else {
            send(msg.userId, { type: 'ERROR', reason: 'reconnect failed' });
          }
          break;
        }

        // Normal join path.
        connections.set(msg.userId, {
          ws: conn.ws,
          userId: msg.userId,
          roomId: msg.roomId,
          isAlive: true,
        });
        conn.userId = msg.userId;
        conn.roomId = msg.roomId;

        const result = room.join({
          userId: msg.userId,
          userName: msg.userName,
          publicProfile: msg.publicProfile,
        });
        if (!result.ok) {
          send(msg.userId, { type: 'ERROR', reason: result.reason });
          connections.delete(msg.userId);
        }
        break;
      }
      case 'MESSAGE': {
        const room = rooms.get(msg.roomId);
        room?.onMessage(msg.userId, msg.content);
        break;
      }
      case 'LEAVE': {
        // Explicit leave: skip grace period entirely.
        const timer = graceTimers.get(msg.userId);
        if (timer) {
          clearTimeout(timer);
          graceTimers.delete(msg.userId);
        }
        const room = rooms.get(msg.roomId);
        room?.leave(msg.userId);
        connections.delete(msg.userId);
        break;
      }
      case 'WATCH_LOBBY': {
        // If the socket was already watching another room, move it.
        if (conn.watchedRoomId && conn.watchedRoomId !== msg.roomId) {
          lobbyWatchers.get(conn.watchedRoomId)?.delete(conn.ws);
        }
        let set = lobbyWatchers.get(msg.roomId);
        if (!set) {
          set = new Set<WebSocket>();
          lobbyWatchers.set(msg.roomId, set);
        }
        set.add(conn.ws);
        conn.watchedRoomId = msg.roomId;

        const existing = rooms.get(msg.roomId);
        const participants = existing?.getParticipants() ?? [];
        sendDirect(conn.ws, {
          type: 'LOBBY_STATE',
          roomId: msg.roomId,
          participants,
          isFull: participants.length >= MAX_PARTICIPANTS,
        });
        break;
      }
      case 'UNWATCH_LOBBY': {
        if (conn.watchedRoomId) {
          lobbyWatchers.get(conn.watchedRoomId)?.delete(conn.ws);
          conn.watchedRoomId = undefined;
        }
        break;
      }
    }
  }

  console.log(`[server] listening on ws://localhost:${opts.port}`);
  const lan = getLanAddresses();
  if (lan.length > 0) {
    console.log('[server] LAN URLs to share with teammates on the same network:');
    for (const ip of lan) {
      console.log(`           ws://${ip}:${opts.port}`);
    }
    console.log(
      '[server] macOS: if teammates cannot connect, check System Settings → Network → Firewall (allow Node).',
    );
  }
  return wss;
}

function findConnectionByWs(
  connections: Map<string, Connection>,
  ws: WebSocket,
): Connection | undefined {
  for (const c of connections.values()) {
    if (c.ws === ws) return c;
  }
  return undefined;
}
