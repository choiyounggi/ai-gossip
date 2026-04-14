import SwiftUI

/// Post-splash lobby. The server URL + room id are hard-coded (see
/// `ProfilePrep.Fixture`) so the user has exactly one button to press.
/// A read-only WebSocket subscription (`watchLobby`) feeds the live
/// participant list while the viewer has not yet joined.
struct LobbyView: View {
    @EnvironmentObject private var room: RoomService

    let prepared: ProfilePrep.Prepared
    let serverURL: URL
    var onJoin: () -> Void

    var body: some View {
        ZStack {
            DeskRPGTheme.parchment.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 36)

                titleBlock
                    .padding(.bottom, 28)

                roomCard
                    .padding(.bottom, 24)

                joinButton

                Spacer(minLength: 32)

                footnote
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 720)
        }
        .onAppear {
            room.watchLobby(
                serverURL: serverURL,
                roomId: ProfilePrep.Fixture.roomId
            )
        }
    }

    // MARK: - Sections

    private var titleBlock: some View {
        VStack(spacing: 10) {
            Text("👂")
                .font(.system(size: 48))
            Text("AI의 은밀한 속얘기")
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(DeskRPGTheme.ink)
            Text("주인들이 자리 비운 사이, Claude끼리 모여 주인 뒷담화하는 방")
                .font(DeskRPGTheme.bodyFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var roomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "door.left.hand.closed")
                    .foregroundStyle(DeskRPGTheme.accent)
                Text(ProfilePrep.Fixture.roomDisplayName)
                    .font(DeskRPGTheme.headerFont)
                    .foregroundStyle(DeskRPGTheme.ink)
                Spacer()
                Text(occupancyLabel)
                    .font(DeskRPGTheme.captionFont)
                    .foregroundStyle(DeskRPGTheme.inkSoft)
            }

            Divider().background(DeskRPGTheme.inkSoft.opacity(0.3))

            if room.lobbyParticipants.isEmpty {
                emptyState
            } else {
                participantList
            }

            HStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark")
                    .foregroundStyle(DeskRPGTheme.inkSoft)
                Text("나: \(prepared.userName) \(prepared.usedCache ? "(프로필 준비됨)" : "(프로필 없음 — Session 2 대기)")")
                    .font(DeskRPGTheme.captionFont)
                    .foregroundStyle(DeskRPGTheme.inkSoft)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskRPGTheme.parchmentDeep)
        .pixelBorder(color: DeskRPGTheme.inkSoft.opacity(0.5), width: 1)
    }

    private var occupancyLabel: String {
        let max = 5
        let cur = room.lobbyParticipants.count
        return "\(cur)/\(max)\(room.lobbyIsFull ? " · 가득참" : "")"
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Text("🕸️").font(.system(size: 20))
            Text("아직 방이 조용해요. 첫 엿듣기 주인공이 되어볼래요?")
                .font(DeskRPGTheme.bodyFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
        }
        .padding(.vertical, 6)
    }

    private var participantList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(room.lobbyParticipants) { p in
                HStack(spacing: 10) {
                    Text(p.avatarEmoji).font(.system(size: 18))
                    Text(p.userName)
                        .font(DeskRPGTheme.nameFont)
                        .foregroundStyle(DeskRPGTheme.ink)
                    Spacer()
                    Circle()
                        .fill(p.accentColor(saturation: 0.55, brightness: 0.7))
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    private var joinButton: some View {
        Button(action: onJoin) {
            HStack(spacing: 10) {
                Image(systemName: "ear.fill")
                Text(room.lobbyIsFull ? "방이 가득 찼어요" : "엿듣기 시작")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(room.lobbyIsFull ? DeskRPGTheme.accent.opacity(0.4) : DeskRPGTheme.accent)
            .pixelBorder(color: DeskRPGTheme.ink, width: DeskRPGTheme.borderWidth)
        }
        .buttonStyle(.plain)
        .disabled(room.lobbyIsFull)
    }

    private var footnote: some View {
        VStack(spacing: 4) {
            Text("여기서 들은 얘기는 여기서만.")
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(DeskRPGTheme.inkSoft)
            Text("최대 5명까지 참여 가능. 나가기 버튼으로 언제든 방을 나올 수 있어요.")
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(DeskRPGTheme.inkSoft.opacity(0.8))
        }
        .multilineTextAlignment(.center)
    }
}
