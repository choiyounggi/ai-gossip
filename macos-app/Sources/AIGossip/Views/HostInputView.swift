import SwiftUI
import Foundation

/// Step 2 of the startup flow — collect + verify the WebSocket host URL.
///
/// The server address is deliberately NOT hard-coded in source: each user
/// enters it here and we persist the value in UserDefaults so the next
/// launch prefills the field. Verification opens an actual WebSocket to
/// the URL with a short deadline so we catch typos / wrong ports / closed
/// firewalls before the user reaches the lobby.
struct HostInputView: View {
    let prepared: ProfilePrep.Prepared
    var onVerified: (URL) -> Void

    private static let defaultsKey = "ai-gossip.lastHostURL"

    @State private var urlText: String = ""
    @State private var status: VerificationStatus = .idle
    @State private var verifyTask: Task<Void, Never>? = nil

    enum VerificationStatus: Equatable {
        case idle
        case verifying
        case failed(String)
    }

    var body: some View {
        ZStack {
            DeskRPGTheme.parchment.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 32)

                header

                greeting

                urlForm
                    .padding(.top, 4)

                verifyButton

                if case .failed(let msg) = status {
                    Text(msg)
                        .font(DeskRPGTheme.captionFont)
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer(minLength: 32)

                footnote
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 720)
        }
        .onAppear {
            if urlText.isEmpty {
                urlText = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
            }
        }
        .onDisappear { verifyTask?.cancel() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Text("🔌")
                .font(.system(size: 52))
            Text("어느 방으로 숨어들까?")
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(DeskRPGTheme.ink)
            Text("친구에게서 받은 호스트 주소를 입력해줘")
                .font(DeskRPGTheme.bodyFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var greeting: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill.checkmark")
                .foregroundStyle(DeskRPGTheme.accent)
            Text("\(prepared.userName)님 환영합니다")
                .font(DeskRPGTheme.nameFont)
                .foregroundStyle(DeskRPGTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DeskRPGTheme.parchmentDeep)
        .pixelBorder(color: DeskRPGTheme.accent.opacity(0.6), width: 1)
    }

    private var urlForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("호스트 URL")
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
            TextField("ws://example.com:8787", text: $urlText)
                .textFieldStyle(.plain)
                .font(DeskRPGTheme.bodyFont)
                .foregroundStyle(DeskRPGTheme.ink)
                .padding(10)
                .background(DeskRPGTheme.parchment)
                .pixelBorder(color: DeskRPGTheme.ink, width: 1)
                .disabled(status == .verifying)
                .onSubmit { verify() }
        }
    }

    private var verifyButton: some View {
        Button(action: verify) {
            HStack(spacing: 10) {
                if status == .verifying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("연결 확인 중...")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                } else {
                    Image(systemName: "network")
                    Text("연결 확인")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(isFormValid ? DeskRPGTheme.accent : DeskRPGTheme.accent.opacity(0.4))
            .pixelBorder(color: DeskRPGTheme.ink, width: DeskRPGTheme.borderWidth)
        }
        .buttonStyle(.plain)
        .disabled(!isFormValid || status == .verifying)
    }

    private var footnote: some View {
        VStack(spacing: 4) {
            Text("호스트 URL은 이 기기에만 저장되고 서버에 공유되지 않아요.")
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
            Text("형식: ws://HOST:PORT (일반) 또는 wss://HOST:PORT (TLS)")
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(DeskRPGTheme.inkSoft.opacity(0.8))
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Validation

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        guard let parsed = URL(string: trimmedURL),
              let scheme = parsed.scheme?.lowercased(),
              parsed.host?.isEmpty == false
        else { return false }
        return scheme == "ws" || scheme == "wss"
    }

    // MARK: - Actions

    private func verify() {
        guard isFormValid, let url = URL(string: trimmedURL) else { return }
        status = .verifying
        verifyTask?.cancel()
        verifyTask = Task { @MainActor in
            let result = await HostReachability.probe(url: url, timeout: 5)
            switch result {
            case .success:
                UserDefaults.standard.set(trimmedURL, forKey: Self.defaultsKey)
                status = .idle
                onVerified(url)
            case .failure(let reason):
                status = .failed(reason)
            }
        }
    }
}

// MARK: - Reachability probe

/// Opens a real WebSocket to the host and waits for the first message or a
/// proper close. We send WATCH_LOBBY (well-formed JSON the server knows) so
/// a correctly-deployed server responds with LOBBY_STATE almost immediately.
/// If the handshake fails or nothing arrives within the deadline we report
/// a human-readable failure and tear the socket down.
enum HostReachability {
    enum Outcome {
        case success
        case failure(String)
    }

    static func probe(url: URL, timeout: TimeInterval) async -> Outcome {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // Fire-and-forget probe frame so the server has a reason to reply.
        let probeJSON = #"{"type":"WATCH_LOBBY","roomId":"\#(ProfilePrep.Fixture.roomId)"}"#
        task.send(.string(probeJSON)) { _ in }

        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return Outcome.failure("응답이 없어요 (타임아웃 \(Int(timeout))초). URL/포트를 확인해줘.")
        }
        let receive = Task { () -> Outcome in
            do {
                _ = try await task.receive()
                return .success
            } catch {
                return .failure("연결 실패: \(error.localizedDescription)")
            }
        }

        let winner = await Task {
            await withTaskGroup(of: Outcome.self) { group in
                group.addTask { await deadline.value }
                group.addTask { await receive.value }
                let first = await group.next() ?? .failure("알 수 없는 오류")
                group.cancelAll()
                return first
            }
        }.value

        task.cancel(with: .normalClosure, reason: nil)
        deadline.cancel()
        receive.cancel()
        return winner
    }
}
