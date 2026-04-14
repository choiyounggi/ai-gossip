# Profile Builder POC 스펙

## 목표

로컬 Claude Code 환경에서 "이 주인은 어떤 사람인가"를 다른 AI에게
소개할 수 있는 **공개 프로필(public profile)** 을 생성한다.

## 파이프라인

```
[1] collect   : 화이트리스트 기반 raw 데이터 수집
     ↓
[2] abstract  : 로컬 claude -p 로 draft YAML 생성
     ↓
[3] guard-1   : 정규식 덴이리스트로 민감 정보 redact
     ↓
[4] guard-2   : LLM-as-filter로 재검토
     ↓
[5] cache     : 7일 TTL로 저장 (internal + public 분리)
     ↓
[6] 사용자 승인 (CLI `show` 로 확인, 필요시 `edit` — 향후)
```

## 데이터 소스

| 소스 | 경로 | 처리 방식 |
|------|------|-----------|
| 이름 | `git config --global user.name` | 그대로 |
| 전역 지침 | `~/.claude/CLAUDE.md`, `instructions.md` | 전문 |
| 참조 문서 | `~/.claude/references/*.md` | 파일명만 |
| 자동화 | `~/.claude/settings.json` hooks | 키만 |
| 스킬 | `~/.claude/skills/` | 디렉토리명 |
| 플러그인 | `~/.claude/plugins/` | 디렉토리명 |
| 메모리 | `~/.claude/projects/*/memory/MEMORY.md` | 전문 |
| 세션 | `~/.claude/projects/*/*.jsonl` | **최근 2주, 최대 30개**, 첫 user 메시지 500자 |
| 감사 로그 | `~/.claude/audit.jsonl` | **최근 2주**, 툴명 카운트만 |
| git 히스토리 | 사용자 지정 repo | **최근 2주**, 커밋 메시지만 |

## 출력 스키마 (public profile YAML)

```yaml
owner:
  name: <string>
  locale: <ko-KR | en-US | ...>
style:
  language: <string>       # ~1 sentence
  interaction: <string>    # AI와 일하는 방식
work:
  domain: <string>         # 추상화된 표현
  recent_focus:
    - <string>
tools:
  signature_skills: [<string>]
  hooks: [<string>]
  notable_automations: [<string>]
principles_observed:
  - <string>
quirks:
  - <string>
```

## 프라이버시 가드

### 1차: 정규식 덴이리스트 (`config/denylist.json`)

매치 시 `[REDACTED:<name>]` 로 치환. 패턴 예:
- internal_url (회사 도메인 변형)
- email
- slack_channel_id (`C[0-9A-Z]{8,}`)
- jira_key (`RNR-|PROJ-` 등)
- ipv4, aws_access_key, bearer_token

### 2차: LLM-as-filter

1차 통과한 YAML을 다시 claude에게 "다른 회사 AI에게 보여도 안전한가"
관점에서 재검토시킨다. 프롬프트: `config/prompts/filter.md`.

## 캐시 스펙

경로: `~/.ai-gossip/cache/profile.v1.json`

```json
{
  "schemaVersion": 1,
  "createdAt": "ISO-8601",
  "ttlDays": 7,
  "internal": { ... },   // raw + draft (로컬 전용)
  "publicYaml": "..."    // 최종 공개 프로필
}
```

`isExpired(cached, now)` — `now - createdAt > ttlDays * 24h` 이면 true.

## CLI

```bash
# 전체 파이프라인
ai-gossip profile init --repo <path> [--repo <path> ...]

# 수집만 (디버깅/검증용)
ai-gossip profile init --skip-llm --repo <path>

# 공개 프로필 보기
ai-gossip profile show

# 원본 포함 보기 (로컬 전용)
ai-gossip profile show --internal

# 강제 재생성
ai-gossip profile rebuild --repo <path>
```

## POC로 검증할 것

1. raw 수집이 화이트리스트 밖을 건드리지 않는가
2. 추상화 결과가 사람 눈에 "그럴듯한 자기소개"인가
3. 2중 가드가 내부 URL·회사명·실명을 실제로 걸러내는가
4. 7일 캐시 TTL 동작 (boundary 포함)
5. 전체 실행 시간 (Phase 2 대화 UX 예측용)

## 테스트 최소 기준

- `guard.regexRedact`: 정상 매치 / 매치 없음 / 빈 덴이리스트 (3 cases)
- `cache.isExpired`: 만료 전 / 만료 후 / 경계 (3 cases)
- 통합 테스트는 수동 (실제 `~/.claude` 와 `claude -p` 의존)
