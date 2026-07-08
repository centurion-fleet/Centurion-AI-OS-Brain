import Foundation
import Network

/// Discovers Centurion devices on the local network using mDNS/Bonjour.
///
/// Centurion OS Desktop advertises itself as `_centurion._tcp` on the
/// local network. The iPhone discovers it without any configuration,
/// cloud dependency, or central server — pure local network discovery.
///
/// This is the first layer of the security model: if you can't reach
/// the Centurion's network, you can't even see it exists.

protocol BonjourDiscovererDelegate: AnyObject {
    func didDiscover(device: CenturionDevice)
    func didLose(device: CenturionDevice)
}

final class BonjourDiscoverer {
    private var browser: NWBrowser?
    private var discoveredDevices: [String: CenturionDevice] = [:]
    weak var delegate: BonjourDiscovererDelegate?
    
    let serviceType = "_centurion._tcp"
    
    func startDiscovery() {
        let params = NWParameters()
        params.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        
        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                print("[Bonjour] Discovery failed: \(error)")
                self?.browser?.cancel()
                // Restart by creating a new browser
                self?.startDiscovery()
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
        
        guard discoveredDevices[key] == nil else { return }
        
        if case .service(let name, let type, let domain, let interface) = result.endpoint {
            // Resolve the service to get IP address and port
            let resolver = NWEndpoint.service(name: name, type: type, domain: domain, interface: interface)
            
            let params = NWParameters.tcp
            let connection = NWConnection(to: resolver, using: params)
            
            let device = CenturionDevice(
                id: UUID(),
                name: name.replacingOccurrences(of: "\\s*\\(\\d+\\)", with: "", options: .regularExpression),
                hostname: "\(name).local",
                ipAddress: "",  // Will be resolved
                port: 0,        // Will be resolved
                publicKey: nil,
                isConnected: false,
                connectionMethod: .lan,
                lastSeen: Date()
            )
            
            discoveredDevices[key] = device
            delegate?.didDiscover(device: device)
        }
    }
    
    private func handleRemoved(_ result: NWBrowser.Result) {
        let key = "\(result.endpoint)"
        if let device = discoveredDevices.removeValue(forKey: key) {
            delegate?.didLose(device: device)
        }
    }
}
