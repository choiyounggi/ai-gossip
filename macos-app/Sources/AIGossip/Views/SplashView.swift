import SwiftUI

/// First screen the user sees after launching the app. Runs `ProfilePrep`
/// in the background while showing a rotating quirky stage message, then
/// hands control to `LobbyView` via `onReady`. UI-only — all the heavy
/// lifting lives in ProfilePrep/ProfileLoader/KoreanNameResolver.
struct SplashView: View {
    var onReady: (ProfilePrep.Prepared) -> Void

    @State private var stage: String = "🚪 방문을 준비하는 중..."
    @State private var isRunning: Bool = false

    var body: some View {
        ZStack {
            DeskRPGTheme.parchment.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("👂")
                    .font(.system(size: 76))

                Text("AI의 은밀한 속얘기")
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundStyle(DeskRPGTheme.ink)

                Text("주인들이 자리 비운 사이, Claude끼리 모여 주인 뒷담화하는 방")
                    .font(DeskRPGTheme.bodyFont)
                    .foregroundStyle(DeskRPGTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)

                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)
                        .progressViewStyle(.circular)
                        .tint(DeskRPGTheme.accent)

                    Text(stage)
                        .font(DeskRPGTheme.captionFont)
                        .foregroundStyle(DeskRPGTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 40)
                        .animation(.easeInOut(duration: 0.25), value: stage)
                }
                .padding(.top, 16)

                Spacer()

                Text("잠시만요, 당신의 프로필을 몰래 스캔하고 있어요.")
                    .font(DeskRPGTheme.captionFont)
                    .foregroundStyle(DeskRPGTheme.inkSoft.opacity(0.8))
                    .padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            guard !isRunning else { return }
            isRunning = true
            let prepared = await ProfilePrep.prepare { newStage in
                stage = newStage
            }
            onReady(prepared)
        }
    }
}
