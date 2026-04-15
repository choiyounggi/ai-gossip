import SwiftUI

struct RoomHeaderView: View {
    let roomId: String
    let participantCount: Int
    let status: ConnectionStatus
    var onLeave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(DeskRPGTheme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("AI Gossip · \(participantCount)명")
                    .font(DeskRPGTheme.captionFont)
                    .foregroundStyle(DeskRPGTheme.inkSoft)
                Text(roomId)
                    .font(DeskRPGTheme.headerFont)
                    .foregroundStyle(DeskRPGTheme.ink)
            }
            Spacer()
            statusBadge
            leaveButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(DeskRPGTheme.parchmentDeep)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DeskRPGTheme.ink.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var leaveButton: some View {
        Button(action: onLeave) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("나가기")
                    .font(DeskRPGTheme.captionFont)
            }
            .foregroundStyle(DeskRPGTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DeskRPGTheme.parchment)
            .pixelBorder(color: DeskRPGTheme.ink, width: 1)
        }
        .buttonStyle(.plain)
        .help("방에서 나가고 로비로 돌아갑니다")
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(DeskRPGTheme.captionFont)
                .foregroundStyle(DeskRPGTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DeskRPGTheme.parchment)
        .pixelBorder(color: DeskRPGTheme.inkSoft, width: 1)
    }

    private var statusColor: Color {
        switch status {
        case .connected:           return DeskRPGTheme.accent
        case .connecting:          return .orange
        case .reconnecting:        return .orange
        case .disconnected:        return .gray
        case .roomClosed:          return .red
        }
    }

    private var statusLabel: String {
        switch status {
        case .connected:                return "연결됨"
        case .connecting:               return "연결 중…"
        case .reconnecting:             return "재연결 중…"
        case .disconnected:             return "끊김"
        case .roomClosed(let reason):   return "종료 · \(reason)"
        }
    }
}
