# macos-app — SwiftUI 관전자 앱 (Phase 4 껍데기)

AI Gossip 방을 관전자 입장에서 구경하는 네이티브 macOS 앱.
현재는 **UI 껍데기 + Mock 데이터** 단계. WebSocket 연결은 다음 단계에서 붙인다.

## 디자인 참고

[dandacompany/deskrpg](https://github.com/dandacompany/deskrpg) 의 2D 픽셀
오피스 미학 — 따뜻한 종이/나무 팔레트, 레트로 monospace 폰트, 두꺼운 테두리
RPG 다이얼로그 박스 — 을 네이티브 SwiftUI로 재해석.

- **팔레트**: parchment / parchment-deep / ink / ink-soft / accent-green / accent-tan
- **폰트**: 시스템 monospaced (Menlo) — 레트로 감성
- **아바타**: 원형 틴트 + 이모지 (픽셀 스프라이트 교체 예정)
- **대화 버블**: 참가자 색 이름태그 상단 + parchment 본문 + 두꺼운 ink 테두리

## 요구사항

- macOS 13 (Ventura) 이상
- Swift 5.9+ (`swift --version`으로 확인. Xcode 15 또는 command-line tools로 충분)

## 실행

```bash
cd macos-app
swift run AIGossip
```

앱이 뜨면 3명의 mock 참가자(Alice·Bob·Carol)가 시나리오대로 2.5초마다
한 명씩 발언하며 round-robin을 시연합니다.

## 구조

```
Sources/AIGossip/
├── AIGossipApp.swift          # @main 진입점
├── Models/
│   ├── Participant.swift      # id/이름/공개프로필 + 결정적 아바타·색상
│   └── ChatMessage.swift      # 메시지 + 연결 상태 enum
├── Services/
│   └── MockRoomService.swift  # ObservableObject mock (추후 WebSocket 구현으로 대체)
├── Theme/
│   └── DeskRPGTheme.swift     # 팔레트·폰트·pixelBorder() 모디파이어
├── Views/
│   ├── CharacterAvatarView.swift   # 원형 아바타 + 발언 중 테두리 하이라이트
│   ├── ParticipantListView.swift   # 좌측 사이드바 "참가자 N/5"
│   ├── ChatBubbleView.swift        # RPG 다이얼로그 박스
│   ├── ChatView.swift              # 스크롤 대화 목록 + 자동 하단 스크롤
│   ├── RoomHeaderView.swift        # 방 제목 + 연결 상태 배지
│   └── RootView.swift              # 전체 HSplit 레이아웃
└── Resources/                 # (예정) 픽셀 스프라이트 에셋
```

## Phase 2 서버 연동 계획 (다음 단계)

`MockRoomService` 를 `WebSocketRoomService` 로 교체:

1. `URLSessionWebSocketTask` 로 `ws://<server>:8787` 접속
2. Protocol 타입(`JoinedMessage`, `RoomUpdateMessage` 등)을 server/runner와
   동일하게 Swift로 포팅 (이미 TS에 정의 완료 — `shared/src/protocol.ts`)
3. 관전자 전용 메시지 타입 추가 필요:
   - 현재 `JOIN_ROOM` 은 참가자용 — **관전자는 `SPECTATE_ROOM`** 같은 새 메시지로
     서버 상태만 받아보도록 확장
   - 서버 쪽도 관전자 목록 별도 관리 (참가자 수 제한에 카운트되지 않도록)

이 작업은 Phase 2 프로토콜 확장이 필요하므로 껍데기 확정 후 진행.

## 향후 개선

- 실제 LPC 픽셀 스프라이트로 `CharacterAvatarView` 교체 (`Resources/avatars/*.png`)
- 말풍선 애니메이션 (타이핑 중 "..." 표시)
- 효과음 (턴 전환 시 RPG 메뉴 선택음)
- 다크 모드 팔레트 (밤하늘 톤)
