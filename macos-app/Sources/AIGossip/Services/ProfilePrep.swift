import Foundation

/// One-stop "app bootstrap" helper used by `SplashView`.
///
/// Session-1 scope: no real Node-style profile-builder yet. We surface
/// whatever Phase-1 profile cache the user might have on disk, otherwise
/// we fall back to a minimal inline YAML so the app is still runnable.
/// Session 2 will replace the fallback branch with a full Swift port of
/// profile-builder (git scan + ~/.claude scan + claude -p summarization).
enum ProfilePrep {

    struct Prepared: Sendable {
        let userName: String        // Korean display name
        let userId: String          // deterministic-ish id sent to server
        let publicProfile: String   // raw YAML shared with other agents
        let usedCache: Bool         // true if we loaded the real Phase-1 cache
    }

    /// Room identity. "비밀 토론방" is the canonical team room for this
    /// demo — addressed as the plain ASCII id `gossip1` on the wire so
    /// URL/JSON encoding never gets in the way, with the Korean label
    /// surfaced in the UI only. The server URL is NOT fixtured here —
    /// each client enters it in HostInputView and it's persisted in
    /// UserDefaults. Keeping the server address out of source lets the
    /// repo stay public without leaking an operator's home IP.
    enum Fixture {
        static let roomId = "gossip1"
        static let roomDisplayName = "비밀 토론방"
    }

    /// Simulates meaningful work on the splash screen even when the real
    /// profile cache is already present. Rotates through several stages
    /// so the quirky copy has time to be read; the *actual* disk reads
    /// are near-instant. Minimum total duration is ~2.5s so the splash
    /// feels intentional rather than flashing past.
    @MainActor
    static func prepare(
        minimumDuration: TimeInterval = 2.5,
        onStage: @escaping (String) -> Void
    ) async -> Prepared {
        let start = Date()

        onStage("👂 당신의 커밋을 몰래 훔쳐보는 중...")
        try? await sleep(0.6)

        let userName = KoreanNameResolver.resolve()

        onStage("🔍 '\(userName)'님의 코딩 습관을 정리 중...")
        try? await sleep(0.7)

        let loaded = ProfileLoader.tryLoad()
        let publicProfile: String
        let usedCache: Bool
        if let loaded, !loaded.publicYaml.isEmpty {
            publicProfile = loaded.publicYaml
            usedCache = true
            onStage("📖 캐시에서 프로필을 꺼내오는 중...")
        } else {
            publicProfile = fallbackProfile(name: userName)
            usedCache = false
            onStage("🧐 주인님의 은밀한 설정들을 훑어보는 중...")
        }
        try? await sleep(0.6)

        onStage("✨ 다른 에이전트들에게 보여줄 소개를 다듬는 중...")
        try? await sleep(0.5)

        // Warmup 단계: claude -p를 미리 한 번 돌려서 플러그인/MCP가
        // splash 화면에서 로드되게 만든다. 매 턴에 뜨던 macOS 권한
        // 다이얼로그(음악·파일 등)가 여기서 한 번에 뜨고 끝남.
        // 24시간 이내 성공 기록이 있으면 스킵.
        if shouldWarmup() {
            onStage("🔒 시스템 권한 다이얼로그가 뜨면 '허용 안 함' 눌러도 됩니다...")
            await ClaudeRunner().warmup()
            markWarmupSuccess()
        }

        // Hold until the minimum duration has elapsed so the splash doesn't
        // flash past before the user can register it.
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimumDuration {
            try? await sleep(minimumDuration - elapsed)
        }

        let userId = makeUserId(for: userName)
        return Prepared(
            userName: userName,
            userId: userId,
            publicProfile: publicProfile,
            usedCache: usedCache
        )
    }

    // MARK: - Warmup cache

    private static let warmupDateKey = "AIGossip.lastWarmupDate"
    private static let warmupTTL: TimeInterval = 24 * 60 * 60  // 24h

    private static func shouldWarmup() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: warmupDateKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) > warmupTTL
    }

    private static func markWarmupSuccess() {
        UserDefaults.standard.set(Date(), forKey: warmupDateKey)
    }

    // MARK: - Helpers

    private static func fallbackProfile(name: String) -> String {
        """
        owner:
          name: \(name)
          locale: ko-KR
        style:
          interaction: (프로필 캐시 없음 — Session 2에서 자동 생성 예정)
        """
    }

    /// Unique enough for a 5-seat room demo; server rejects duplicates anyway.
    private static func makeUserId(for name: String) -> String {
        let slug = name
            .applyingTransform(.latinToHangul, reverse: true)?  // 한글 → 라틴
            .applyingTransform(.stripDiacritics, reverse: false) ?? name
        let cleaned = slug
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let base = cleaned.isEmpty ? "u" : cleaned
        return "\(base)-\(UUID().uuidString.prefix(4))"
    }

    private static func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
