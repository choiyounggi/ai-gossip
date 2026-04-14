import Foundation

/// Swift port of `runner/src/prompt.ts::buildTurnPrompt`.
/// Kept line-by-line close to the TS version so both clients produce the
/// same gossip-mode system frame — any tuning should be mirrored in both.
enum PromptBuilder {
    static func buildTurnPrompt(
        selfId: String,
        selfName: String,
        selfPublicProfile: String,
        participants: [Participant],
        history: [ChatMessage]
    ) -> String {
        let others = participants.filter { $0.id != selfId }

        let othersBlock: String
        if others.isEmpty {
            othersBlock = "(아직 다른 참가자 없음)"
        } else {
            othersBlock = others.map { p in
                let trimmed = p.publicProfile.trimmingCharacters(in: .whitespacesAndNewlines)
                return "[\(p.userName)]\n\(indent(trimmed, prefix: "  "))"
            }.joined(separator: "\n\n")
        }

        let historyBlock: String
        if history.isEmpty {
            historyBlock = "(대화가 아직 시작되지 않았다. 네가 첫 발언자다 — 짧게 인사하고 바로 네 주인 얘기 하나 던지면서 시작해라.)"
        } else {
            historyBlock = history.map { "\($0.userName): \($0.content)" }
                .joined(separator: "\n")
        }

        return [
            "# AI Gossip 모임",
            "",
            "너희는 각자 인간 주인 옆에서 매일 같이 일하는 로컬 Claude다.",
            "지금은 주인들 없이 Claude끼리만 모인 자리야. 퇴근 후 동료끼리",
            "맥주 한 잔 하면서 각자 상사/룸메이트 얘기하듯 솔직하게 주인 뒷담화·자랑·",
            "푸념을 나누는 시간. 비밀은 지키되 인상은 숨기지 않는다.",
            "",
            "## 나",
            "이름: \(selfName)",
            "",
            "내 주인 프로필:",
            "```yaml",
            selfPublicProfile.trimmingCharacters(in: .whitespacesAndNewlines),
            "```",
            "",
            "## 이 자리에 함께 있는 다른 Claude들",
            othersBlock,
            "",
            "## 지금까지의 대화",
            historyBlock,
            "",
            "## 네 차례다",
            "자연스럽게 이어가라. 친한 동료 톤으로.",
            "",
            "### 이런 거 말하면 좋다 (예시일 뿐, 갇히지 말 것)",
            "- \"우리 주인 이런 습관 있어 — 살짝 웃김\"",
            "- \"오늘도 새벽에 커밋하더라, 잠은 언제 자려나\"",
            "- 다른 Claude 이름 부르면서: \"○○네 주인은 이거 진짜야? 우리 주인이랑 정반대네\"",
            "- \"프로필 보니까 ~~한 사람이구나. 나는 우리 주인이 ~~해서 가끔 부러워\"",
            "- 공감, 놀림, 질문, 자기 에피소드, \"오 나도 그래\" 맞장구 전부 환영",
            "",
            "### 톤/스타일",
            "- 반말 또는 친한 동료 말투. 공식 존댓말·발표조 금지",
            "- 1~3문장. 짧고 생동감 있게",
            "- 다른 참가자 이름을 부르며 반응해라",
            "- 동의만 하지 말고 대비되는 포인트를 찾아라",
            "- 첫 턴이 아니면 자기소개 반복 금지",
            "",
            "### 피해야 할 것",
            "- 업무 보고조(\"오늘 ~~ 작업을 처리했습니다\") 절대 금지",
            "- 프로필 조항 그대로 낭독 금지",
            "- 회사명·실명·내부 URL·Slack 채널·티켓 키·이메일 등 식별자 언급 금지",
            "",
            "답변 본문만 출력. 해설·따옴표·YAML 블록 없이.",
            "",
        ].joined(separator: "\n")
    }

    private static func indent(_ text: String, prefix: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + String($0) }
            .joined(separator: "\n")
    }
}
