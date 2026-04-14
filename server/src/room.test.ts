import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Room } from './room.ts';
import type {
  Participant,
  ServerToClient,
} from './protocol.ts';

interface Sent {
  to: string;
  msg: ServerToClient;
}

function setup() {
  const sent: Sent[] = [];
  const room = new Room('r1', (to, msg) => sent.push({ to, msg }));
  return { room, sent };
}

function p(userId: string, userName = userId): Participant {
  return { userId, userName, publicProfile: `owner:\n  name: ${userName}` };
}

function first<T extends ServerToClient['type']>(
  sent: Sent[],
  to: string,
  type: T,
): Extract<ServerToClient, { type: T }> | undefined {
  const found = sent.find((s) => s.to === to && s.msg.type === type);
  return found?.msg as Extract<ServerToClient, { type: T }> | undefined;
}

test('join < 2 participants does NOT dispatch YOUR_TURN', () => {
  const { room, sent } = setup();
  assert.deepEqual(room.join(p('alice')), { ok: true });
  assert.equal(sent.some((s) => s.msg.type === 'YOUR_TURN'), false);
});

test('second join triggers first YOUR_TURN for alice (first joiner)', () => {
  const { room, sent } = setup();
  room.join(p('alice'));
  room.join(p('bob'));
  const turn = first(sent, 'alice', 'YOUR_TURN');
  assert.ok(turn, 'alice should receive YOUR_TURN');
  assert.equal(turn.turn, 1);
});

test('round-robin across 3 participants: A → B → C → A', () => {
  const { room, sent } = setup();
  room.join(p('a'));
  room.join(p('b'));
  room.join(p('c'));

  const order: string[] = [];
  const capture = () => {
    for (const s of sent.splice(0)) {
      if (s.msg.type === 'YOUR_TURN') order.push(s.to);
    }
  };
  capture();
  room.onMessage('a', 'hi');
  capture();
  room.onMessage('b', 'hello');
  capture();
  room.onMessage('c', 'hey');
  capture();

  assert.deepEqual(order, ['a', 'b', 'c', 'a']);
});

test('out-of-turn MESSAGE is ignored', () => {
  const { room, sent } = setup();
  room.join(p('a'));
  room.join(p('b'));
  sent.splice(0);
  room.onMessage('b', 'butting in'); // not b's turn yet
  assert.equal(sent.some((s) => s.msg.type === 'ROOM_UPDATE'), false);
});

test('LEAVE with >2 participants keeps room open and dispatches next turn', () => {
  const { room, sent } = setup();
  room.join(p('a'));
  room.join(p('b'));
  room.join(p('c'));
  sent.splice(0);

  room.leave('a'); // a was current turn holder
  assert.equal(room.isClosed, false);
  // current index was 0 (a); after removal, b is at index 0
  const next = sent.filter((s) => s.msg.type === 'YOUR_TURN').pop();
  assert.equal(next?.to, 'b');
});

test('LEAVE leaving only 1 participant closes the room', () => {
  const { room, sent } = setup();
  room.join(p('a'));
  room.join(p('b'));
  sent.splice(0);

  room.leave('b');
  assert.equal(room.isClosed, true);
  const closed = sent.find((s) => s.msg.type === 'ROOM_CLOSED');
  assert.ok(closed);
});

test('6th join rejected with "room full"', () => {
  const { room } = setup();
  room.join(p('a'));
  room.join(p('b'));
  room.join(p('c'));
  room.join(p('d'));
  room.join(p('e'));
  const result = room.join(p('f'));
  assert.deepEqual(result, { ok: false, reason: 'room full (max 5)' });
});

test('duplicate userId join rejected', () => {
  const { room } = setup();
  room.join(p('a'));
  const result = room.join(p('a', 'alice-again'));
  assert.deepEqual(result, { ok: false, reason: 'already joined' });
});

test('join dispatches ROOM_SNAPSHOT to the newcomer with current history', () => {
  const { room, sent } = setup();
  room.join(p('a'));
  room.join(p('b'));
  room.onMessage('a', 'hi');
  room.onMessage('b', 'hello');
  sent.splice(0);

  room.join(p('c'));

  const snapshot = first(sent, 'c', 'ROOM_SNAPSHOT');
  assert.ok(snapshot, 'newcomer should receive a ROOM_SNAPSHOT');
  assert.equal(snapshot.history.length, 2, 'snapshot carries prior messages');
  assert.equal(snapshot.history[0].content, 'hi');
  assert.equal(snapshot.history[1].content, 'hello');
  assert.equal(snapshot.participants.length, 3);
});

test('ROOM_SNAPSHOT is NOT sent to existing participants on new join', () => {
  const { room, sent } = setup();
  room.join(p('a'));
  room.join(p('b'));
  sent.splice(0);

  room.join(p('c'));

  const snapshotToA = first(sent, 'a', 'ROOM_SNAPSHOT');
  const snapshotToB = first(sent, 'b', 'ROOM_SNAPSHOT');
  assert.equal(snapshotToA, undefined, 'a should not receive snapshot');
  assert.equal(snapshotToB, undefined, 'b should not receive snapshot');
});

test('history is captured and bounded', () => {
  const { room } = setup();
  room.join(p('a'));
  room.join(p('b'));
  for (let i = 0; i < 50; i += 1) {
    const turnHolder = i % 2 === 0 ? 'a' : 'b';
    room.onMessage(turnHolder, `msg-${i}`);
  }
  const hist = room.getHistory();
  assert.ok(hist.length <= 80, `history should be bounded, got ${hist.length}`);
  assert.equal(hist[hist.length - 1].content, 'msg-49');
});
