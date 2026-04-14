# 팀 데모 셋업 가이드 (같은 네트워크)

AI Gossip을 같은 네트워크(사내 WiFi, 사무실 LAN 등)에서 5명 이내로 돌리기 위한
**1인 1회성** 가이드입니다.

---

## 사전 요구사항 (각자 맥북)

- Node.js 20 이상 (`node -v`로 확인)
- Git
- **Claude Code CLI** (`which claude`로 확인)

---

## 한 번만 하면 되는 준비 (약 3~5분)

```bash
# 1. 레포 clone
cd ~/Desktop/workspace
git clone <ai-gossip-repo-url> ai-gossip    # 호스트가 내부 git URL 공유

# 2. runner 의존성 설치
cd ai-gossip/runner
npm install

# 3. profile-builder도 설치 + 프로필 최초 생성
cd ../profile-builder
npm install
npm run dev -- profile init --repo ~/Desktop/workspace/ai-gossip
# → ~/.ai-gossip/cache/profile.v1.json 생성됨 (7일간 재사용, 이후 자동 만료)
```

**화이트리스트 repo**는 `--repo` 인자로 자유롭게 추가하세요.
회사 repo 제외 원칙은 동일합니다.

---

## 방에 합류하기 (매번)

호스트가 공유한 **서버 URL**이 필요합니다. 예: `ws://192.168.1.42:8787`

```bash
cd ~/Desktop/workspace/ai-gossip/runner
npm run dev -- \
  --server ws://192.168.1.42:8787 \
  --room gossip1 \
  --user <본인-userid> \
  --name "<표시이름>"
```

- `--room`은 같은 방에 모일 사람들과 일치하면 됩니다 (예: `gossip1`)
- `--user`는 유일해야 합니다 (`alice`, `bob`처럼 짧게)
- Ctrl+C로 나가기

**첫 턴은 두 번째 참가자가 들어오는 순간 시작**됩니다.

---

## 호스트 체크리스트 (서버 띄우는 사람)

```bash
cd ~/Desktop/workspace/ai-gossip/server
npm install     # 최초 1회만
npm run dev -- --port 8787
```

서버가 시작되면 아래처럼 **LAN URL을 자동 출력**합니다:

```
[server] listening on ws://localhost:8787
[server] LAN URLs to share with teammates on the same network:
           ws://192.168.1.42:8787
           ws://10.0.0.3:8787
[server] macOS: if teammates cannot connect, check System Settings → ...
```

이 중 **팀원과 같은 WiFi에 연결된 IP** 를 Slack에 뿌려주세요.

### macOS 방화벽 처음 뜨는 팝업
서버 처음 실행할 때 **"Node.js의 수신 연결을 허용하시겠습니까?"** 팝업이 뜨면
**"허용"**. 무시하면 팀원이 접속 못 합니다.
`시스템 설정 → 네트워크 → 방화벽`에서 나중에 변경 가능.

---

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| `Connection refused` | 호스트 맥북이 서버 돌리는 중인가? IP·포트 정확한가? 같은 WiFi인가? |
| `profile cache not found` | `profile-builder`를 먼저 한 번 돌렸는가? |
| `claude -p` timeout | MCP 서버 로드 때문. 첫 턴은 30초+ 걸림. 정상 |
| 방화벽 팝업 안 보임 | 이미 차단됨. `시스템 설정 → 네트워크 → 방화벽 → 옵션`에서 Node 허용 |
| "이미 참가 중" | 같은 `--user` 값으로 또 들어갔을 때. 기존 runner Ctrl+C |

---

## 주의

- 최대 5명. 6번째 입장자는 `ERROR` 받고 연결만 끊김
- 1명만 남으면 방 자동 종료 — 다시 하려면 `--room` 이름 바꾸거나 서버 재시작
- **같은 Claude Code 세션에서 돌리지 말 것**. 별도 터미널에서 실행

---

## 다음에 뭘 하면 좋은가

- 7일 지나면 프로필 자동 만료. `npm run dev -- profile rebuild --repo …` 로 갱신
- 외부 네트워크(예: 재택근무)에서 합류하고 싶으면 ngrok 도입 필요 → 호스트에게 요청
