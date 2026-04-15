/**
 * Wire protocol for AI Gossip Phase 2.
 * Both `server` and `runner` import from this module via relative path.
 */

export const MAX_PARTICIPANTS = 5;
export const HISTORY_WINDOW = 20;

export interface Participant {
  userId: string;
  userName: string;
  /** Raw YAML from Phase 1 profile-builder (publicYaml). */
  publicProfile: string;
}

export interface ChatMessage {
  userId: string;
  userName: string;
  content: string;
  /** ISO-8601 timestamp. */
  timestamp: string;
  /** Monotonically increasing per room, assigned by the server on MESSAGE. */
  seq: number;
}

// --- Client → Server ---

export interface JoinRoomMessage {
  type: 'JOIN_ROOM';
  roomId: string;
  userId: string;
  userName: string;
  publicProfile: string;
  /**
   * Reconnect hint. If set, the server treats this JOIN_ROOM as a resume:
   * it replaces the existing socket for `userId` and replies with a
   * ROOM_SNAPSHOT containing only messages where `seq > sinceSeq`.
   */
  sinceSeq?: number;
}

export interface ClientChatMessage {
  type: 'MESSAGE';
  roomId: string;
  userId: string;
  content: string;
}

export interface LeaveMessage {
  type: 'LEAVE';
  roomId: string;
  userId: string;
}

/**
 * Read-only subscription for the lobby screen — lets clients watch who's
 * currently in a room without actually joining (no participant slot
 * consumed, no turn rotation). Converted to a real participant once the
 * same socket sends JOIN_ROOM.
 */
export interface WatchLobbyMessage {
  type: 'WATCH_LOBBY';
  roomId: string;
}

export interface UnwatchLobbyMessage {
  type: 'UNWATCH_LOBBY';
  roomId: string;
}

export type ClientToServer =
  | JoinRoomMessage
  | ClientChatMessage
  | LeaveMessage
  | WatchLobbyMessage
  | UnwatchLobbyMessage;

// --- Server → Client ---

export interface JoinedMessage {
  type: 'JOINED';
  roomId: string;
  participants: Participant[];
}

export interface YourTurnMessage {
  type: 'YOUR_TURN';
  roomId: string;
  turn: number;
  history: ChatMessage[];
  participants: Participant[];
}

export interface RoomUpdateMessage {
  type: 'ROOM_UPDATE';
  roomId: string;
  message: ChatMessage;
}

export interface RoomClosedMessage {
  type: 'ROOM_CLOSED';
  roomId: string;
  reason: string;
}

export interface ErrorMessage {
  type: 'ERROR';
  reason: string;
}

/**
 * Sent only to the joining participant, right after JOIN_ROOM is accepted.
 * Carries the recent history + current participants so a late joiner can
 * immediately render context instead of waiting until YOUR_TURN.
 */
export interface RoomSnapshotMessage {
  type: 'ROOM_SNAPSHOT';
  roomId: string;
  history: ChatMessage[];
  participants: Participant[];
}

/**
 * Broadcast to every socket that has sent WATCH_LOBBY for this room.
 * Emitted whenever a participant joins or leaves — powers the lobby's
 * live participant list before the viewer has joined.
 */
export interface LobbyStateMessage {
  type: 'LOBBY_STATE';
  roomId: string;
  participants: Participant[];
  isFull: boolean;
}

export type ServerToClient =
  | JoinedMessage
  | YourTurnMessage
  | RoomUpdateMessage
  | RoomClosedMessage
  | ErrorMessage
  | RoomSnapshotMessage
  | LobbyStateMessage;
