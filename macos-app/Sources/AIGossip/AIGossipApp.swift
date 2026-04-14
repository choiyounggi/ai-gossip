import SwiftUI
import AppKit

/// AppDelegate bridges macOS lifecycle events into our Swift stack.
/// - `applicationDidFinishLaunching` promotes the process to a regular
///   GUI app when launched via `swift run` (otherwise the activation
///   policy leaves us stuck out of the dock).
/// - `applicationShouldTerminateAfterLastWindowClosed` quits cleanly.
/// - `applicationWillTerminate` flushes the RoomService so the WebSocket
///   + in-flight `claude -p` subprocess don't outlive the GUI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var room: RoomService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort — if we never reached .room, shutdown() is still safe.
        Task { @MainActor in
            room?.shutdown()
        }
    }
}

enum AppRoute {
    case splash
    case hostInput
    case lobby
    case room
}

@main
struct AIGossipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var room = RoomService()
    @State private var route: AppRoute = .splash
    @State private var prepared: ProfilePrep.Prepared?
    @State private var hostURL: URL?

    var body: some Scene {
        WindowGroup("AI Gossip") {
            Group {
                switch route {
                case .splash:
                    SplashView { prep in
                        self.prepared = prep
                        self.route = .hostInput
                    }
                case .hostInput:
                    if let prepared {
                        HostInputView(prepared: prepared) { verifiedURL in
                            self.hostURL = verifiedURL
                            self.route = .lobby
                        }
                    } else {
                        SplashView { prep in
                            self.prepared = prep
                            self.route = .hostInput
                        }
                    }
                case .lobby:
                    if let prepared, let hostURL {
                        LobbyView(prepared: prepared, serverURL: hostURL, onJoin: handleJoin)
                    } else {
                        // Shouldn't happen — host-input always sets hostURL before flipping.
                        SplashView { prep in
                            self.prepared = prep
                            self.route = .hostInput
                        }
                    }
                case .room:
                    RootView(onLeave: handleLeave)
                }
            }
            .environmentObject(room)
            .frame(minWidth: 900, minHeight: 600)
            .onAppear { appDelegate.room = room }
        }
        .windowStyle(.titleBar)
    }

    private func handleJoin() {
        guard let p = prepared, let url = hostURL else { return }
        room.connect(
            serverURL: url,
            roomId: ProfilePrep.Fixture.roomId,
            userId: p.userId,
            userName: p.userName,
            publicProfile: p.publicProfile
        )
        route = .room
    }

    private func handleLeave() {
        room.leave()
        route = .lobby
    }
}
