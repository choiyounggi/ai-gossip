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
}

export interface StartServerOptions {
  port: number;
}

export function startServer(opts: StartServerOptions): WebSocketServer {
  const wss = new WebSocketServer({ port: opts.port });
  const connections = new Map<string, Connection>(); // by userId
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

  wss.on('connection', (ws) => {
    const conn: Connection = { ws };

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
        room?.leave(conn.userId);
        connections.delete(conn.userId);
      }
      if (conn.watchedRoomId) {
        lobbyWatchers.get(conn.watchedRoomId)?.delete(ws);
      }
    });

    ws.on('error', (err) => {
      console.error('[ws] socket error:', err.message);
    });
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
        connections.set(msg.userId, {
          ws: conn.ws,
          userId: msg.userId,
          roomId: msg.roomId,
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
