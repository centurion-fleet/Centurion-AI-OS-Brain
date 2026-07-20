import Foundation
import Network

/// Discovers Centurion devices on the local network using mDNS/Bonjour.
///
/// Centurion on Linux, Mac, or Windows advertises itself as `_centurion._tcp` on the
/// local network. The iPhone discovers it without any configuration,
/// cloud dependency, or central server — pure local network discovery.
///
/// This is the first layer of the security model: if you can't reach
/// the Sovereign's network, you can't even see it exists.

protocol BonjourDiscovererDelegate: AnyObject {
    func didDiscover(device: CenturionDevice)
    func didLose(device: CenturionDevice)
    func didFailDiscovery(message: String)
}

final class BonjourDiscoverer {
    private var browser: NWBrowser?
    private var discoveredDevices: [String: CenturionDevice] = [:]
    weak var delegate: BonjourDiscovererDelegate?

    let serviceType = "_centurion._tcp"
    private let defaultPort = 9119

    func startDiscovery() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.browser?.cancel()
                self?.delegate?.didFailDiscovery(
                    message: "We couldn't search your network. Allow local network access for Sovereign Remote in Settings."
                )
                print("[Bonjour] Discovery failed: \(error)")
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            for result in results {
                self?.handleDiscovered(result)
            }
            for change in changes {
                if case .removed(let result) = change {
                    self?.handleRemoved(result)
                }
            }
        }

        browser?.start(queue: .main)
        print("[Bonjour] Started discovering \(serviceType)")
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        discoveredDevices.removeAll()
        print("[Bonjour] Stopped discovery")
    }

    // MARK: - Private

    private func handleDiscovered(_ result: NWBrowser.Result) {
        let key = "\(result.endpoint)"
        guard case .service(let name, let type, let domain, _) = result.endpoint else { return }

        let metadata = parseMetadata(result.metadata)
        let displayName = name.replacingOccurrences(
            of: "\\s*\\(\\d+\\)",
            with: "",
            options: .regularExpression
        )
        let hostname = metadata.hostname
        let port = metadata.port ?? defaultPort

        if var existing = discoveredDevices[key] {
            existing = CenturionDevice(
                id: existing.id,
                name: displayName,
                hostname: hostname,
                ipAddress: existing.ipAddress,
                port: port,
                serviceName: name,
                serviceType: type,
                serviceDomain: domain,
                publicKey: existing.publicKey,
                isConnected: existing.isConnected,
                connectionMethod: .lan,
                lastSeen: Date()
            )
            discoveredDevices[key] = existing
            delegate?.didDiscover(device: existing)
            return
        }

        let device = CenturionDevice(
            id: stableDeviceID(for: key),
            name: displayName,
            hostname: hostname,
            ipAddress: "",
            port: port,
            serviceName: name,
            serviceType: type,
            serviceDomain: domain,
            publicKey: nil,
            isConnected: false,
            connectionMethod: .lan,
            lastSeen: Date()
        )

        discoveredDevices[key] = device
        delegate?.didDiscover(device: device)
    }

    private func handleRemoved(_ result: NWBrowser.Result) {
        let key = "\(result.endpoint)"
        if let device = discoveredDevices.removeValue(forKey: key) {
            delegate?.didLose(device: device)
        }
    }

    private func stableDeviceID(for endpointKey: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in endpointKey.utf8.enumerated() {
            bytes[index % 16] ^= byte
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private struct ServiceMetadata {
        var hostname: String = ""
        var port: Int?
        var version: String = ""
        var requiresPairing: Bool = true
    }

    private func parseMetadata(_ metadata: NWBrowser.Result.Metadata?) -> ServiceMetadata {
        guard let metadata,
              case let .bonjour(record) = metadata else {
            return ServiceMetadata()
        }

        var parsed = ServiceMetadata()
        if let hostname = record["hostname"] {
            parsed.hostname = hostname
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        if let version = record["version"] {
            parsed.version = version
        }
        if let requiresPairing = record["requires_pairing"] {
            parsed.requiresPairing = requiresPairing != "false"
        }
        if let transport = record["transport"], transport == "tcp-v1" {
            parsed.port = defaultPort
        }
        return parsed
    }
}
