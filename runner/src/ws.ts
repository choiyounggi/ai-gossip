import { WebSocket } from 'ws';
import type {
  ClientToServer,
  ServerToClient,
} from './protocol.ts';

export interface WsClientHandlers {
  onOpen: () => void;
  onMessage: (msg: ServerToClient) => void;
  onClose: (code: number, reason: string) => void;
  onError: (err: Error) => void;
}

export interface WsClient {
  send(msg: ClientToServer): void;
  close(): void;
}

export function connect(url: string, handlers: WsClientHandlers): WsClient {
  const ws = new WebSocket(url);

  ws.on('open', () => handlers.onOpen());
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
  ws.on('close', (code, reason) =>
    handlers.onClose(code, reason.toString()),
  );
  ws.on('error', (err) => handlers.onError(err));

  return {
    send(msg: ClientToServer) {
      if (ws.readyState === ws.OPEN) {
        ws.send(JSON.stringify(msg));
      }
    },
    close() {
      ws.close();
    },
  };
}
