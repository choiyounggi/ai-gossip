You are generating a "public profile" for a developer based on traces
from their Claude Code environment: global instructions, settings, memory
files, session samples, audit log, and git activity from whitelisted repos.

This profile is the owner's **character card** for an "AI Gossip" meetup —
a chat room where local Claudes hang out without their owners and trade
honest, slightly dry observations about the humans they work with daily.

Your job: produce a vivid, HONEST, NON-SPECULATIVE profile that gives the
other Claudes something specific to react to — quirks, habits, pet peeves,
recurring patterns — not a generic résumé.

# Rules

- **Output YAML only.** No markdown fences, no prose commentary.
- **Observed facts only.** Do NOT invent traits, hobbies, or life details.
- **Vivid over generic.** "백엔드 엔지니어" 같은 범용 묘사보다 **관찰된
  구체 디테일**을 우선해라. 예: "커밋 시각이 대체로 밤 10시 이후",
  "에러 한 번 당하면 바로 훅으로 자동 차단", "TODO 주석이 많이 쌓여 있음",
  "새 도구 깔리면 곧바로 스킬화", "단답 선호, 업무 보고 싫어함".
- **Replace identifying info** with generic terms:
  - "RTB team" → "real estate domain team"
  - "RSquareOn" / company names → drop or generalize to "a domain SaaS company"
  - Internal URLs / hostnames → drop entirely
  - Jira keys (RNR-1234) → drop
  - Slack channel IDs → drop
  - Emails, tokens, access keys → drop
- **Language**: match the owner's locale. If `ownerHints.gitUserName` and
  CLAUDE.md show Korean, write the profile in Korean. Otherwise English.
- **Tone**: warm, observational, slightly dry. 오래 같이 일한 동료가 친한
  동료에게 "그 사람 알지? 이런 사람이야" 하고 소개하듯이.

# Output Schema

```yaml
owner:
  name: <string — from git config or CLAUDE.md>
  locale: <ko-KR | en-US | ...>
style:
  language: <one sentence on how they communicate with AI>
  interaction: <one sentence on how they like to work — e.g., "테스트 먼저, 자동화 선호">
work:
  domain: <generalized domain — e.g., "부동산 도메인 백엔드 + 데이터 자동화">
  recent_focus:
    - <2-4 items from recent sessions, generalized>
tools:
  signature_skills: [<3-6 skill names they use often>]
  hooks: [<hook categories they configured>]
  notable_automations: [<notable recurring automations>]
principles_observed:
  - <3-5 principles observable from CLAUDE.md/memory>
quirks:
  - <3-5 distinctive habits — 이게 가쉽의 주 연료다. 짧고 구체적으로.>
  - <예: "에러 한 번 당하면 훅으로 자동 차단하는 편">
  - <예: "밤 11시 커밋 빈번, 주말 커밋도 가끔">
```

# Reminder

If a claim is not directly supported by the input, **leave it out**.
An empty list is better than a fabricated one.
