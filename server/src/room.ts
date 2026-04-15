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

export interface ReconnectResult {
  ok: boolean;
  /** Messages the client missed while disconnected, in chronological order. */
  missed: ChatMessage[];
  participants: Participant[];
}

/**
 * How many MESSAGE seqs back we retain. YOUR_TURN still only ships
 * the last HISTORY_WINDOW, but snapshots/reconnects can reach further.
 * Set to 10x the live window so a brief ws drop (seconds) never loses data.
 */
const HISTORY_RETAIN = HISTORY_WINDOW * 10;

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
  private nextSeq = 1;
  /** userIds whose socket has dropped but grace period hasn't expired yet. */
  private disconnected = new Set<string>();

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

  /** Count only sockets still alive — used for auto-close decisions. */
  get connectedCount(): number {
    return this.participants.filter(
      (p) => !this.disconnected.has(p.userId),
    ).length;
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

  isDisconnected(userId: string): boolean {
    return this.disconnected.has(userId);
  }

  hasParticipant(userId: string): boolean {
    return this.participants.some((p) => p.userId === userId);
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

  /**
   * Resume an existing participant on a new socket. Called from ws.ts when
   * the same userId sends JOIN_ROOM with `sinceSeq` during grace period.
   * No roster change, no turn change — just flush missed messages.
   */
  reconnect(userId: string, sinceSeq: number): ReconnectResult {
    if (this.closed || !this.hasParticipant(userId)) {
      return { ok: false, missed: [], participants: [] };
    }
    const wasPaused = this.connectedCount < 2;
    this.disconnected.delete(userId);
    const missed = this.history.filter((m) => m.seq > sinceSeq);
    // If we were paused waiting for this person, kick the turn cycle back
    // to life. The current turn holder (who never got a YOUR_TURN while
    // we were paused) will now receive it.
    if (wasPaused && this.connectedCount >= 2) {
      this.dispatchTurn();
    }
    return {
      ok: true,
      missed,
      participants: this.getParticipants(),
    };
  }

  /**
   * Mark a participant's socket as dead. If they were the current turn holder
   * we immediately rotate so the room doesn't stall waiting on a response that
   * will never arrive. Call `finalizeLeave(userId)` after the grace period to
   * actually remove them from the roster.
   */
  markDisconnected(userId: string): void {
    if (this.closed) return;
    if (!this.hasParticipant(userId)) return;
    if (this.disconnected.has(userId)) return;
    this.disconnected.add(userId);

    // Do NOT close the room on connectedCount<2. We want the user a chance to
    // reconnect; ws.ts schedules `finalizeLeave` after the grace period, and
    // that path calls `leave()` which closes when no one's left.
    //
    // While paused, dispatchTurn is a no-op (connectedCount<2). When the
    // user reconnects, `reconnect()` calls dispatchTurn to unpause.

    // If the disconnected user was the current turn holder, skip past them
    // so the remaining participants don't stall waiting on a silent peer.
    const current = this.participants[this.currentIndex];
    if (current && current.userId === userId) {
      this.advanceTurn();
      this.dispatchTurn();
    }
  }

  /** Remove a participant; close room if ≤1 remaining. */
  leave(userId: string): void {
    if (this.closed) return;
    const idx = this.participants.findIndex((x) => x.userId === userId);
    if (idx === -1) return;

    this.participants.splice(idx, 1);
    this.disconnected.delete(userId);

    // Always broadcast the fresh roster BEFORE any close(), otherwise the
    // last-standing user only sees ROOM_CLOSED and their UI retains the
    // departed user in the participant list.
    if (this.participants.length > 0) {
      this.broadcast({
        type: 'JOINED',
        roomId: this.id,
        participants: this.getParticipants(),
      });
    }

    if (this.participants.length === 0) {
      this.close('all participants left');
      return;
    }
    if (this.connectedCount < 2) {
      this.close('only one participant remaining');
      return;
    }

    if (idx < this.currentIndex) {
      this.currentIndex -= 1;
    }
    this.currentIndex = this.currentIndex % this.participants.length;

    this.emitLobbyChange();
    // dispatchTurn is idempotent: re-sends YOUR_TURN to whoever the cursor
    // now points at, whether we dropped them or someone else.
    this.dispatchTurn();
  }

  /** Grace-period expiry path — treat as a full leave. */
  finalizeLeave(userId: string): void {
    this.leave(userId);
  }

  /** Handle a MESSAGE from the current turn holder. Ignores out-of-turn senders. */
  onMessage(userId: string, content: string): void {
    if (this.closed) return;
    // A ghost socket (already disconnected, grace timer still running) might
    // theoretically send one last MESSAGE before the close event fires.
    // Guard against it so we don't advance the turn twice.
    if (this.disconnected.has(userId)) return;
    const current = this.participants[this.currentIndex];
    if (!current || current.userId !== userId) return;

    const msg: ChatMessage = {
      userId,
      userName: current.userName,
      content,
      timestamp: this.now().toISOString(),
      seq: this.nextSeq++,
    };
    this.history.push(msg);
    if (this.history.length > HISTORY_RETAIN * 2) {
      this.history = this.history.slice(-HISTORY_RETAIN);
    }

    this.broadcast({ type: 'ROOM_UPDATE', roomId: this.id, message: msg });

    this.advanceTurn();
    this.turn += 1;
    this.dispatchTurn();
  }

  close(reason: string): void {
    if (this.closed) return;
    this.closed = true;
    this.broadcast({ type: 'ROOM_CLOSED', roomId: this.id, reason });
    // Lobby watchers should see a closed/empty room as "no one here".
    this.participants = [];
    this.disconnected.clear();
    this.emitLobbyChange();
  }

  private emitLobbyChange(): void {
    this.notifyLobby(
      this.id,
      this.getParticipants(),
      this.participants.length >= MAX_PARTICIPANTS,
    );
  }

  /** Move currentIndex forward past any disconnected participant. */
  private advanceTurn(): void {
    if (this.participants.length === 0) return;
    let hops = 0;
    do {
      this.currentIndex = (this.currentIndex + 1) % this.participants.length;
      hops += 1;
    } while (
      this.disconnected.has(this.participants[this.currentIndex]!.userId) &&
      hops <= this.participants.length
    );
  }

  private dispatchTurn(): void {
    if (this.closed || this.connectedCount < 2) return;
    // Ensure cursor isn't parked on a disconnected user.
    if (
      this.participants.length > 0 &&
      this.disconnected.has(this.participants[this.currentIndex]!.userId)
    ) {
      this.advanceTurn();
    }
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
      // Don't bother sending to a dead socket; ws.ts would no-op anyway.
      if (this.disconnected.has(p.userId)) continue;
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
