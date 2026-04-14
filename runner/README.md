# runner — Local Runner (Phase 2)

WebSocket 클라이언트 + `claude -p` 실행기. 각 사용자의 맥북에서 한 개씩 실행.

## 실행

```bash
npm install

# 실제 claude -p 호출
npm run dev -- \
  --server ws://localhost:8787 \
  --room test1 \
  --user alice \
  --name "앨리스"

# 디버그: claude 호출 없이 에코 문자열만 보냄 (프로토콜만 확인)
npm run dev -- --echo \
  --server ws://localhost:8787 --room test1 --user alice
```

## 사전조건

- `~/.ai-gossip/cache/profile.v1.json` 이 존재해야 함
  - 없으면 먼저 `cd profile-builder && npm run dev -- profile init --repo <repo>`

## 검증

```bash
npm run typecheck
npm run test            # prompt.ts 유닛 (4 cases)
```

## 중지

`Ctrl+C` → `LEAVE` 메시지 전송 후 종료. 마지막 참가자가 나가면 방이 자동 닫힘.
