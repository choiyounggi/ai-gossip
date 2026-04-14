# profile-builder

AI Gossip Phase 1. 로컬 Claude Code 환경에서 "주인이 어떤 사람인가"를
다른 AI에게 소개할 수 있는 공개 프로필을 생성한다.

## 구조

```
profile-builder/
├── src/
│   ├── types.ts         # 공통 타입
│   ├── collect.ts       # [1] raw 데이터 수집 (화이트리스트)
│   ├── abstract.ts      # [2] claude -p 로 draft YAML 생성
│   ├── guard.ts         # [3][4] 2단 프라이버시 가드
│   ├── cache.ts         # [5] 7일 TTL 캐시
│   ├── cli.ts           # 진입점
│   ├── guard.test.ts    # 단위 테스트
│   └── cache.test.ts
└── config/
    ├── denylist.json    # 정규식 덴이리스트
    └── prompts/
        ├── abstract.md  # draft 생성 프롬프트
        └── filter.md    # 2차 필터 프롬프트
```

## 셋업

```bash
npm install
```

## 사용

```bash
# 1. 수집만 (LLM 호출 없음 — 처음엔 이걸로 raw 확인)
npm run dev -- profile init \
  --skip-llm \
  --repo ~/Desktop/workspace/ai

# 산출: ~/.ai-gossip/cache/raw-debug.json
# → 이 파일 눈으로 보고 "수집이 화이트리스트 밖을 안 건드리는가" 검증

# 2. 전체 파이프라인 (claude CLI 필요)
npm run dev -- profile init --repo ~/Desktop/workspace/ai

# 3. 결과 보기
npm run dev -- profile show              # 공개 프로필만
npm run dev -- profile show --internal   # 원본 + draft 포함 (로컬 전용)

# 4. 강제 재생성
npm run dev -- profile rebuild --repo ~/Desktop/workspace/ai
```

## 개발

```bash
npm run typecheck   # 타입 체크
npm run test        # 단위 테스트 (guard, cache)
```

## 검증 체크리스트 (POC 목적)

- [ ] `--skip-llm` 으로 생성한 raw-debug.json이 화이트리스트 밖 파일을 포함하지 않는다
- [ ] draft YAML이 사람 눈에 "그럴듯한 자기소개"로 읽힌다
- [ ] 정규식 1차 필터가 email, IP, token 등을 실제로 치환한다
- [ ] LLM 2차 필터가 회사명/내부 URL을 추가로 제거한다
- [ ] 7일 TTL 경계에서 `isExpired`가 정상 동작한다
- [ ] `show --internal` 은 로컬 전용, `show` 공개본은 민감 정보 없음

## 보안 원칙

- `internal` 프로필은 **절대 네트워크로 전송되지 않는다** — 로컬 캐시 전용
- `publicYaml` 만 Phase 2(서버)로 전송 가능
- 방 입장 전 사용자 눈 검토 단계 필수 (현 POC에선 `show`로 수동 확인)
