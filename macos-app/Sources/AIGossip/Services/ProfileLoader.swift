import Foundation

/// Reads the Phase-1 profile-builder cache so the Swift client can send a
/// real publicProfile on JOIN_ROOM instead of a hand-rolled stub. The cache
/// is a plain JSON file written by `profile-builder`; we only consume the
/// fields needed for sharing + lobby status display.
enum ProfileLoader {

    static let defaultCachePath: String = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".ai-gossip/cache/profile.v1.json")

    /// Throwing load — use when you need to know *why* a profile is missing.
    static func load(from path: String = defaultCachePath) throws -> LoadedProfile {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProfileLoaderError.notFound(path: path)
        }
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProfileLoaderError.readFailed(underlying: error)
        }

        let payload: ProfileCachePayload
        do {
            payload = try JSONDecoder().decode(ProfileCachePayload.self, from: data)
        } catch {
            throw ProfileLoaderError.decodeFailed(underlying: error)
        }

        let trimmedYaml = payload.publicYaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedYaml.isEmpty else {
            throw ProfileLoaderError.invalidFormat(reason: "publicYaml 비어있음")
        }

        let createdAt = parseISO8601(payload.createdAt) ?? Date()
        return LoadedProfile(
            publicYaml: trimmedYaml,
            createdAt: createdAt,
            ttlDays: payload.ttlDays
        )
    }

    /// Non-throwing variant — returns nil on any error. Suited to the lobby
    /// status card which simply renders "있음 / 없음" states.
    static func tryLoad(from path: String = defaultCachePath) -> LoadedProfile? {
        try? load(from: path)
    }

    private static func parseISO8601(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: s)
    }
}

struct LoadedProfile: Equatable {
    let publicYaml: String
    let createdAt: Date
    let ttlDays: Int

    var ageInDays: Double {
        Date().timeIntervalSince(createdAt) / 86_400
    }

    var isExpired: Bool {
        ageInDays > Double(ttlDays)
    }
}

enum ProfileLoaderError: Error, LocalizedError {
    case notFound(path: String)
    case readFailed(underlying: Error)
    case decodeFailed(underlying: Error)
    case invalidFormat(reason: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let p):      return "프로필 캐시 없음: \(p)"
        case .readFailed(let e):    return "캐시 읽기 실패: \(e.localizedDescription)"
        case .decodeFailed(let e):  return "캐시 파싱 실패: \(e.localizedDescription)"
        case .invalidFormat(let r): return "캐시 포맷 이상: \(r)"
        }
    }
}

/// Subset of profile-builder's `CachedProfile` (see
/// profile-builder/src/cache.ts) — unknown keys are dropped by JSONDecoder.
private struct ProfileCachePayload: Decodable {
    let createdAt: String
    let ttlDays: Int
    let publicYaml: String
}
