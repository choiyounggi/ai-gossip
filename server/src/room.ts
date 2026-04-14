import type {
  ChatMessage,
  Participant,
  ServerToClient,
} from './protocol.ts';
import {
  HISTORY_WINDOW,
  MAX_PARTICIPANTS,
} from './protocol.ts';

export type Send = (userId: string, msg: ServerToClient) => void;

/**
 * Notifies external lobby watchers (sockets that sent WATCH_LOBBY but never
 * joined) that the participant roster has changed. Implemented by ws.ts so
 * Room stays free of transport/watcher bookkeeping.
 */
export type NotifyLobbyChange = (
  roomId: string,
  participants: Participant[],
  isFull: boolean,
) => void;

export type JoinResult =
  | { ok: true }
  | { ok: false; reason: string };

/**
 * Pure state container for a single chat room.
 * Network I/O is injected via `send` / `broadcast` hooks.
 */
export class Room {
  readonly id: string;
  private participants: Participant[] = [];
  private history: ChatMessage[] = [];
  private currentIndex = 0;
  private turn = 0;
  private closed = false;

  constructor(
    id: string,
    private readonly send: Send,
    private readonly now: () => Date = () => new Date(),
    private readonly notifyLobby: NotifyLobbyChange = () => {},
  ) {
    this.id = id;
  }

  get participantCount(): number {
    return this.participants.length;
  }

  get isClosed(): boolean {
    return this.closed;
  }

  getParticipants(): Participant[] {
    return [...this.participants];
  }

  getHistory(): ChatMessage[] {
    return [...this.history];
  }

  /** Add a participant. Returns {ok:false} if full, already-joined, or closed. */
  join(p: Participant): JoinResult {
    if (this.closed) return { ok: false, reason: 'room closed' };
    if (this.participants.some((x) => x.userId === p.userId)) {
      return { ok: false, reason: 'already joined' };
    }
    if (this.participants.length >= MAX_PARTICIPANTS) {
      return { ok: false, reason: `room full (max ${MAX_PARTICIPANTS})` };
    }
    this.participants.push(p);

    // Late-joiner context: only the newcomer gets history so they can render
    // past messages immediately. Everyone else already has them in-memory.
    this.send(p.userId, {
      type: 'ROOM_SNAPSHOT',
      roomId: this.id,
      history: this.history.slice(-HISTORY_WINDOW),
      participants: this.getParticipants(),
    });

    // Broadcast JOINED state to everyone so UIs stay in sync.
    this.broadcast({
      type: 'JOINED',
      roomId: this.id,
      participants: this.getParticipants(),
    });
    this.emitLobbyChange();

    // When we cross the 2-participant threshold for the first time, start the turn cycle.
    if (this.participants.length === 2 && this.turn === 0) {
      this.dispatchTurn();
    }
    return { ok: true };
  }

  /** Remove a participant; close room if ≤1 remaining. */
  leave(userId: string): void {
    if (this.closed) return;
    const idx = this.participants.findIndex((x) => x.userId === userId);
    if (idx === -1) return;

    this.participants.splice(idx, 1);

    // Adjust currentIndex so the turn cursor stays valid.
    if (this.participants.length === 0) {
      this.close('all participants left');
      return;
    }
    if (this.participants.length < 2) {
      this.close('only one participant remaining');
      return;
    }
    if (idx < this.currentIndex) {
      this.currentIndex -= 1;
    }
    this.currentIndex = this.currentIndex % this.participants.length;

    this.broadcast({
      type: 'JOINED',
      roomId: this.id,
      participants: this.getParticipants(),
    });
    this.emitLobbyChange();
    this.dispatchTurn();
  }

  /** Handle a MESSAGE from the current turn holder. Ignores out-of-turn senders. */
  onMessage(userId: string, content: string): void {
    if (this.closed) return;
    const current = this.participants[this.currentIndex];
    if (!current || current.userId !== userId) return;

    const msg: ChatMessage = {
      userId,
      userName: current.userName,
      content,
      timestamp: this.now().toISOString(),
    };
    this.history.push(msg);
    if (this.history.length > HISTORY_WINDOW * 4) {
      // Trim cheaply; YOUR_TURN only sends last HISTORY_WINDOW anyway.
      this.history = this.history.slice(-HISTORY_WINDOW * 2);
    }

    this.broadcast({ type: 'ROOM_UPDATE', roomId: this.id, message: msg });

    this.currentIndex = (this.currentIndex + 1) % this.participants.length;
    this.turn += 1;
    this.dispatchTurn();
  }

  close(reason: string): void {
    if (this.closed) return;
    this.closed = true;
    this.broadcast({ type: 'ROOM_CLOSED', roomId: this.id, reason });
    // Lobby watchers should see a closed/empty room as "no one here".
    this.participants = [];
    this.emitLobbyChange();
  }

  private emitLobbyChange(): void {
    this.notifyLobby(
      this.id,
      this.getParticipants(),
      this.participants.length >= MAX_PARTICIPANTS,
    );
  }

  private dispatchTurn(): void {
    if (this.closed || this.participants.length < 2) return;
    const next = this.participants[this.currentIndex];
    if (!next) return;
    this.send(next.userId, {
      type: 'YOUR_TURN',
      roomId: this.id,
      turn: this.turn + 1,
      history: this.history.slice(-HISTORY_WINDOW),
      participants: this.getParticipants(),
    });
  }

  private broadcast(msg: ServerToClient): void {
    for (const p of this.participants) {
      this.send(p.userId, msg);
    }
  }
}

export class RoomManager {
  private rooms = new Map<string, Room>();

  constructor(
    private readonly send: Send,
    private readonly notifyLobby: NotifyLobbyChange = () => {},
  ) {}

  getOrCreate(roomId: string): Room {
    let room = this.rooms.get(roomId);
    if (!room || room.isClosed) {
      room = new Room(roomId, this.send, undefined, this.notifyLobby);
      this.rooms.set(roomId, room);
    }
    return room;
  }

  get(roomId: string): Room | undefined {
    return this.rooms.get(roomId);
  }

  remove(roomId: string): void {
    this.rooms.delete(roomId);
  }
}
