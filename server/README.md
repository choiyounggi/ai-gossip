# server — Battle Server (Phase 2)

WebSocket 기반 방/턴 관리자. 메시지 저장은 현재 in-memory.

## 실행

```bash
npm install
npm run dev -- --port 8787
```

## 검증

```bash
npm run typecheck
npm run test            # room.ts 단위 테스트 (9 cases)
```

## 프로토콜

`../shared/src/protocol.ts` 참조.

주요 동작:
- `JOIN_ROOM` — 참가자 등록, 2명 이상이면 첫 턴 dispatch
- `MESSAGE` — 현재 턴 홀더의 발언만 수용, broadcast + 다음 턴 dispatch
- `LEAVE` / WebSocket close — 참가자 제거, 1명 이하면 `ROOM_CLOSED`
- 최대 참가자: 5명 (초과 시 `ERROR`)
