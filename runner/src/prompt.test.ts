import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTurnPrompt } from './prompt.ts';
import type {
  ChatMessage,
  Participant,
} from './protocol.ts';

const alice: Participant = {
  userId: 'alice',
  userName: '앨리스',
  publicProfile: 'owner:\n  name: 앨리스\nstyle:\n  language: ko',
};
const bob: Participant = {
  userId: 'bob',
  userName: '밥',
  publicProfile: 'owner:\n  name: 밥',
};

test('first-turn prompt flags that no conversation has started yet', () => {
  const out = buildTurnPrompt({
    selfUserId: 'alice',
    selfName: '앨리스',
    selfPublicProfile: alice.publicProfile,
    participants: [alice, bob],
    history: [],
  });
  assert.match(out, /첫 발언자/);
  assert.match(out, /\[밥\]/, 'other participant listed');
  assert.doesNotMatch(
    out,
    /## 이 자리에 함께 있는 다른 Claude들[\s\S]*?\[앨리스\]/,
    'self should not be in others block',
  );
});

test('later-turn prompt includes formatted history', () => {
  const history: ChatMessage[] = [
    { userId: 'alice', userName: '앨리스', content: '안녕', timestamp: 't1', seq: 1 },
    { userId: 'bob', userName: '밥', content: '반가워', timestamp: 't2', seq: 2 },
  ];
  const out = buildTurnPrompt({
    selfUserId: 'alice',
    selfName: '앨리스',
    selfPublicProfile: alice.publicProfile,
    participants: [alice, bob],
    history,
  });
  assert.match(out, /앨리스: 안녕/);
  assert.match(out, /밥: 반가워/);
  assert.doesNotMatch(out, /첫 발언자/);
});

test('empty participants list (edge case) is rendered gracefully', () => {
  const out = buildTurnPrompt({
    selfUserId: 'alice',
    selfName: '앨리스',
    selfPublicProfile: alice.publicProfile,
    participants: [alice],
    history: [],
  });
  assert.match(out, /아직 다른 참가자 없음/);
});

test('gossip-mode framing & anti-patterns are always present', () => {
  const out = buildTurnPrompt({
    selfUserId: 'alice',
    selfName: '앨리스',
    selfPublicProfile: alice.publicProfile,
    participants: [alice, bob],
    history: [],
  });
  // 사회적 프레임: 단순 "대화방"이 아니라 "가쉽 모임"임을 명시
  assert.match(out, /AI Gossip 모임/);
  assert.match(out, /주인들 없이 Claude끼리/);
  // 안티 패턴: 업무 보고조, 프로필 낭독 명시 금지
  assert.match(out, /업무 보고조/);
  assert.match(out, /프로필 조항 그대로 낭독 금지/);
  // 프라이버시 가드는 유지
  assert.match(out, /회사명.*실명.*내부 URL/);
});

test('tone hints are explicit (반말, 짧게, 이름 부르기)', () => {
  const out = buildTurnPrompt({
    selfUserId: 'alice',
    selfName: '앨리스',
    selfPublicProfile: alice.publicProfile,
    participants: [alice, bob],
    history: [],
  });
  assert.match(out, /반말 또는 친한 동료 말투/);
  assert.match(out, /1~3문장/);
  assert.match(out, /다른 참가자 이름을 부르며 반응/);
});
