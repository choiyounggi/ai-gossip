import { WebSocket } from 'ws';
import type {
  ClientToServer,
  ServerToClient,
} from './protocol.ts';

export interface WsClientHandlers {
  onOpen: () => void;
  onMessage: (msg: ServerToClient) => void;
  /**
   * Called when the socket has been permanently given up on (LEAVE sent,
   * or reconnect attempts exhausted). Transient disconnects during the
   * auto-reconnect loop do NOT fire this.
   */
  onClose: (code: number, reason: string) => void;
  onError: (err: Error) => void;
  /**
   * Called every time the socket opens (initial + every reconnect). The
   * caller uses this to re-send JOIN_ROOM with `sinceSeq` so missed
   * messages can be replayed.
   */
  onReconnect?: () => void;
}

export interface WsClient {
  send(msg: ClientToServer): void;
  close(): void;
}

/**
 * After this many consecutive failed reconnect attempts we stop trying and
 * invoke onClose. Caps total wait at roughly backoffCap * maxAttempts.
 */
const MAX_RECONNECT_ATTEMPTS = 10;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CAP_MS = 30_000;

/**
 * Auto-reconnecting ws client. Exponential backoff (1s → 2s → 4s … capped
 * at 30s) on close, fires `onOpen` once (initial connect) and `onReconnect`
 * for every subsequent successful reopen so the caller can send JOIN_ROOM
 * with `sinceSeq` to recover missed messages.
 */
export function connect(url: string, handlers: WsClientHandlers): WsClient {
  let ws: WebSocket | null = null;
  let closedByUser = false;
  let reconnectAttempts = 0;
  let hasConnectedOnce = false;
  let reconnectTimer: NodeJS.Timeout | null = null;

  const open = (): void => {
    if (closedByUser) return;
    ws = new WebSocket(url);
    ws.on('open', () => {
      reconnectAttempts = 0;
      if (!hasConnectedOnce) {
        hasConnectedOnce = true;
        handlers.onOpen();
      } else if (handlers.onReconnect) {
        handlers.onReconnect();
      }
    });
    ws.on('message', (raw) => {
      try {
        const parsed = JSON.parse(raw.toString()) as ServerToClient;
        handlers.onMessage(parsed);
      } catch (err) {
        handlers.onError(
          new Error(`invalid server message: ${err instanceof Error ? err.message : String(err)}`),
        );
      }
    });
    ws.on('close', (code, reason) => {
      const reasonStr = reason.toString();
      if (closedByUser) {
        handlers.onClose(code, reasonStr);
        return;
      }
      // The server uses 4000 when it resumes us on a different socket. That's
      // a signal to stop, not to retry: there's already a live connection.
      if (code === 4000) {
        handlers.onClose(code, reasonStr);
        return;
      }
      reconnectAttempts += 1;
      if (reconnectAttempts > MAX_RECONNECT_ATTEMPTS) {
        console.error(
          `[ws] giving up after ${MAX_RECONNECT_ATTEMPTS} reconnect attempts`,
        );
        handlers.onClose(code, reasonStr);
        return;
      }
      const delay = Math.min(
        BACKOFF_BASE_MS * 2 ** (reconnectAttempts - 1),
        BACKOFF_CAP_MS,
      );
      console.log(
        `[ws] disconnected (${code}); reconnecting in ${delay}ms (attempt ${reconnectAttempts})`,
      );
      reconnectTimer = setTimeout(open, delay);
    });
    ws.on('error', (err) => handlers.onError(err));
  };

  open();

  return {
    send(msg: ClientToServer) {
      if (ws && ws.readyState === ws.OPEN) {
        ws.send(JSON.stringify(msg));
      }
    },
    close() {
      closedByUser = true;
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      ws?.close();
    },
  };
}
