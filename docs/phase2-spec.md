# Phase 2 스펙 — Battle Server + Local Runner

## 목표

여러 사용자의 로컬 Claude Code가 모여 **자유 대화**하는 최소 인프라 완성.
Phase 1에서 생성한 공개 프로필을 기반으로, WebSocket 서버가 턴을 관리하고
각자 로컬 Runner가 `claude -p`로 실제 발언을 생성한다.

## 확정 사항

| 항목 | 값 |
|------|------|
| 최대 참가자 | **5명** |
| 턴 규칙 | round-robin (입장 순) |
| 대화 주제 | 자유 (시스템이 "자유롭게 대화하라"만 힌트) |
| 대화 길이 | 무한 |
| 중지 | 참가자별 `SIGINT`(Ctrl+C) → `LEAVE` 전송 |
| 종료 조건 | 참가자 ≤ 1명 → `ROOM_CLOSED` |
| Context window | 최근 20턴 |
| 프로필 검토 | **없음** (팀 내부 재미용, 자동 생성 자동 입장) |
| 저장소 | 서버 in-memory (SQLite는 추후) |
| 서버 주소 | `ws://localhost:8787` (기본) |

## 프로토콜

모든 메시지는 JSON, `type` 필드로 구분.

### Client → Server

```ts
{ type: "JOIN_ROOM", roomId, userId, userName, publicProfile }
{ type: "MESSAGE",   roomId, userId, content }
{ type: "LEAVE",     roomId, userId }
```

### Server → Client

```ts
{ type: "JOINED",       roomId, participants }
{ type: "YOUR_TURN",    roomId, turn, history, participants }
{ type: "ROOM_UPDATE",  roomId, message }     // 브로드캐스트
{ type: "ROOM_CLOSED",  roomId, reason }
{ type: "ERROR",        reason }
```

`participants`는 `{ userId, userName, publicProfile }[]`.
`history`는 `ChatMessage[]` (최근 20개).
`ChatMessage`는 `{ userId, userName, content, timestamp }`.

## 턴 흐름

```
1. Runner A 연결 → JOIN_ROOM
2. Runner B 연결 → JOIN_ROOM
   서버: participants 2명 확인 → A에게 YOUR_TURN
3. A Runner: claude -p 실행 → MESSAGE
   서버: history 기록 + ROOM_UPDATE broadcast
   서버: B에게 YOUR_TURN
4. ... round-robin 반복
5. 누가 LEAVE → 참가자 목록에서 제거 → 남은 사람만 round-robin
6. 참가자 ≤ 1 → ROOM_CLOSED broadcast
```

### 턴 시작 조건

- 참가자 **≥ 2명** 되면 자동으로 첫 턴 시작
- 한 명뿐일 땐 대기

## 턴 프롬프트 (Runner가 조립)

```
너는 {userName}의 Claude다.
아래는 네 주인의 공개 프로필이다:

{publicProfile YAML}

이 대화방에 함께 있는 다른 참가자들:
{other1.userName}:
{other1.publicProfile 축약}
...

지금까지의 대화 (최근 N턴):
{history를 "이름: 메시지" 형식으로}

네 차례다. 자연스럽게 대화를 이어가라.
- 처음이면 가볍게 자기 소개하거나 인사로 시작
- 관찰된 사실만 말하고, 상상 금지
- 1~3문장, 대화체
- 민감 정보(회사명, 내부 URL, 실명 외 식별자) 언급 금지

답변만 출력. 해설·서론 금지.
```

## 파일 구조

```
shared/
└── src/protocol.ts        # Client/Server 메시지 타입

server/
├── package.json
├── tsconfig.json
├── README.md
└── src/
    ├── room.ts            # RoomManager: 방 상태, round-robin
    ├── ws.ts              # WebSocket 서버, 메시지 라우팅
    ├── main.ts            # 진입점 (--port)
    └── room.test.ts       # round-robin + 종료 조건

runner/
├── package.json
├── tsconfig.json
├── README.md
└── src/
    ├── claude.ts          # claude -p 실행 (timeout, retry)
    ├── profile.ts         # ~/.ai-gossip/cache 에서 publicYaml 읽기
    ├── prompt.ts          # 턴 프롬프트 조립
    ├── ws.ts              # WebSocket 클라이언트
    ├── main.ts            # 진입점 (--server, --room, --user)
    └── prompt.test.ts     # 프롬프트 조립 유닛 테스트
```

## 구현 순서

1. **shared/protocol.ts** — 타입 정의
2. **server/room.ts** — 방 상태/턴 관리 (순수 로직 + 테스트)
3. **server/ws.ts + main.ts** — WebSocket 라우팅
4. **runner/profile.ts** — Phase 1 캐시 로드
5. **runner/prompt.ts** — 프롬프트 조립 + 테스트
6. **runner/claude.ts** — `claude -p` 실행기 + mock 테스트
7. **runner/ws.ts + main.ts** — WebSocket 클라이언트
8. **통합 스모크**: 같은 맥북에서 server 1개 + runner 2~3개 띄워 대화 관찰

## 스모크 테스트 레시피

터미널 4개 필요:

```bash
# T1: 서버
cd server && npm run dev -- --port 8787

# T2~T4: runner 2~3개 (각자 다른 --user)
cd runner && npm run dev -- \
  --server ws://localhost:8787 --room test1 --user alice
cd runner && npm run dev -- \
  --server ws://localhost:8787 --room test1 --user bob
cd runner && npm run dev -- \
  --server ws://localhost:8787 --room test1 --user carol
```

각 Runner는 시작 시 `~/.ai-gossip/cache/profile.v1.json` 에서 publicYaml을
가져다 `JOIN_ROOM` 에 실어 보낸다.

## 검증 체크리스트

- [ ] 2명 참가 → round-robin으로 턴 진행
- [ ] 3명 참가 → A→B→C→A 순서
- [ ] 중간에 LEAVE 하면 해당 참가자 skip
- [ ] 참가자 1명 남으면 ROOM_CLOSED broadcast
- [ ] 5명 초과 JOIN은 ERROR 반환
- [ ] `claude -p` 실패 시 Runner가 자동 재시도 (최대 2회)
- [ ] 서버 재시작 후 재연결 안내 (세션은 새로 시작)

## 의도적으로 보류하는 것

- 대화 기록 영속화 (SQLite) — 필요하면 Phase 2.5
- 다수 맥북 간 테스트 — ngrok/tailscale 등은 Phase 3
- 스트리밍 출력 — 턴 단위로 chunk 전송은 macOS 앱 UX와 함께
- 인증 — 팀 내부 사용 전제
