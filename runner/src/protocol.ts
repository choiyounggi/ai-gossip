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

export type ClientToServer = JoinRoomMessage | ClientChatMessage | LeaveMessage;

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

export type ServerToClient =
  | JoinedMessage
  | YourTurnMessage
  | RoomUpdateMessage
  | RoomClosedMessage
  | ErrorMessage
  | RoomSnapshotMessage;
