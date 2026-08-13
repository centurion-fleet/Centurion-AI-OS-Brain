import Foundation

/// RelayTransport envelopes for Chat-from-anywhere (Supabase Realtime).
/// LAN Crypto Chat TCP stays preferred when reachable — this path is away-only.
///
/// Mirrors `centurion_cli/relay_transport.py`: chunk before decrypt, reconnect = re-KX.
enum RelayTransport {
    static let defaultChunkBytes = 180_000
    static let defaultMaxReassembled = 1_048_576

    struct Envelope: Codable, Equatable {
        var v: Int
        var conn: String
        var id: String
        var kind: String
        var chunk_i: Int
        var chunk_n: Int
        var body_b64: String
    }

    final class Session {
        private(set) var conn: String
        private(set) var sessionKeysValid = false
        private var parts: [String: [Int: Data]] = [:]
        private var meta: [String: (conn: String, n: Int, kind: String)] = [:]
        private var waiting: Set<String> = []
        let chunkBytes: Int
        let maxReassembled: Int

        init(
            chunkBytes: Int = RelayTransport.defaultChunkBytes,
            maxReassembled: Int = RelayTransport.defaultMaxReassembled
        ) {
            self.chunkBytes = chunkBytes
            self.maxReassembled = maxReassembled
            self.conn = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }

        @discardableResult
        func resetConnection() -> String {
            parts.removeAll()
            meta.removeAll()
            waiting.removeAll()
            sessionKeysValid = false
            conn = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            return conn
        }

        func markKxComplete() {
            sessionKeysValid = true
        }

        func adoptConn(_ epoch: String) {
            let trimmed = epoch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != conn else { return }
            parts.removeAll()
            meta.removeAll()
            waiting.removeAll()
            sessionKeysValid = false
            conn = trimmed
        }

        func expectResponse(id: String) {
            waiting.insert(id)
        }

        func failInflightIds() -> [String] {
            Array(waiting)
        }

        func outboundFrame(body: Data, expectResponse: Bool = true) throws -> [Envelope] {
            guard sessionKeysValid else {
                throw RelayError.requiresReKx
            }
            if body.count > maxReassembled {
                throw RelayError.payloadTooLarge
            }
            let msgId = UUID().uuidString
            if expectResponse {
                waiting.insert(msgId)
            }
            return Self.split(body: body, conn: conn, msgId: msgId, kind: "frame", chunkBytes: chunkBytes)
        }

        func outboundKx(body: Data, client: Bool) -> [Envelope] {
            let msgId = UUID().uuidString
            return Self.split(
                body: body,
                conn: conn,
                msgId: msgId,
                kind: client ? "kx_client" : "kx_server",
                chunkBytes: chunkBytes
            )
        }

        func ingest(_ env: Envelope) throws -> Data? {
            guard env.conn == conn else {
                throw RelayError.staleConn
            }
            guard env.chunk_n >= 1, env.chunk_i >= 0, env.chunk_i < env.chunk_n else {
                throw RelayError.invalidChunk
            }
            guard let chunk = Data(base64Encoded: env.body_b64) else {
                throw RelayError.invalidChunk
            }
            if env.chunk_n == 1 {
                if chunk.count > maxReassembled { throw RelayError.payloadTooLarge }
                if waiting.contains(env.id) {
                    waiting.remove(env.id)
                }
                return chunk
            }
            if meta[env.id] == nil {
                meta[env.id] = (env.conn, env.chunk_n, env.kind)
                parts[env.id] = [:]
            } else if let m = meta[env.id],
                      (m.conn != env.conn || m.n != env.chunk_n || m.kind != env.kind) {
                throw RelayError.invalidChunk
            }
            var bag = parts[env.id] ?? [:]
            guard bag[env.chunk_i] == nil else { throw RelayError.invalidChunk }
            bag[env.chunk_i] = chunk
            parts[env.id] = bag
            guard bag.count == env.chunk_n else { return nil }
            var ordered = Data()
            for i in 0..<env.chunk_n {
                ordered.append(bag[i] ?? Data())
            }
            parts.removeValue(forKey: env.id)
            meta.removeValue(forKey: env.id)
            if waiting.contains(env.id) {
                waiting.remove(env.id)
            }
            if ordered.count > maxReassembled { throw RelayError.payloadTooLarge }
            return ordered
        }

        private static func split(
            body: Data,
            conn: String,
            msgId: String,
            kind: String,
            chunkBytes: Int
        ) -> [Envelope] {
            if body.isEmpty {
                return [
                    Envelope(
                        v: 1,
                        conn: conn,
                        id: msgId,
                        kind: kind,
                        chunk_i: 0,
                        chunk_n: 1,
                        body_b64: Data().base64EncodedString()
                    ),
                ]
            }
            let n = max(1, Int(ceil(Double(body.count) / Double(chunkBytes))))
            var out: [Envelope] = []
            for i in 0..<n {
                let start = i * chunkBytes
                let end = min(body.count, start + chunkBytes)
                let slice = body.subdata(in: start..<end)
                let outKind = (n > 1 && (kind == "frame" || kind == "frame_chunk"))
                    ? "frame_chunk"
                    : kind
                out.append(
                    Envelope(
                        v: 1,
                        conn: conn,
                        id: msgId,
                        kind: outKind,
                        chunk_i: i,
                        chunk_n: n,
                        body_b64: slice.base64EncodedString()
                    )
                )
            }
            return out
        }
    }

    enum RelayError: Error, LocalizedError {
        case requiresReKx
        case payloadTooLarge
        case staleConn
        case invalidChunk
        case brainOffline

        var errorDescription: String? {
            switch self {
            case .requiresReKx:
                return "Relay reconnected — run key exchange again, then retry."
            case .payloadTooLarge:
                return "That message is too large for Chat from anywhere. Try on home Wi‑Fi."
            case .staleConn:
                return "Relay session expired. Reconnect and try again."
            case .invalidChunk:
                return "Relay received a damaged packet. Retry the turn."
            case .brainOffline:
                return "Your Sovereign is offline. Chat from anywhere needs the Brain online."
            }
        }
    }
}
