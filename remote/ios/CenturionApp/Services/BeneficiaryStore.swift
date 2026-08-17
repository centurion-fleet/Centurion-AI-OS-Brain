import Foundation

/// Family Beneficiary Program — colleague referrals earn Centurions for family.
@MainActor
final class BeneficiaryStore: ObservableObject {
    @Published private(set) var snapshot: BeneficiarySnapshot = .empty
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published var showRewardCelebration = false
    @Published var lastRewardedName: String?

    private let cacheKey = "centurion.beneficiary.snapshot.v1"
    private var previousSuccessfulCount = 0

    init() {
        loadCachedSnapshot()
    }

    var referralsRequired: Int {
        max(snapshot.referralsRequired, 4)
    }

    var beneficiaryFirstName: String {
        snapshot.currentCycle.familyBeneficiaryFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasBeneficiary: Bool {
        !beneficiaryFirstName.isEmpty
    }

    var successfulCount: Int {
        snapshot.currentCycle.successfulColleagueCount
    }

    var colleagueReferrals: [ColleagueReferral] {
        snapshot.currentCycle.colleagueReferrals
    }

    /// Plain-text list for Share Sheet — names + customer credit status.
    var referralShareText: String {
        var lines: [String] = [
            "Family Beneficiary referrals",
            "Earning for: \(hasBeneficiary ? beneficiaryFirstName : "(not nominated yet)")",
            "Progress: \(successfulCount) of \(referralsRequired) customer purchases credited",
            "",
        ]
        if colleagueReferrals.isEmpty {
            lines.append("No referrals shared yet.")
        } else {
            lines.append(contentsOf: colleagueReferrals.map(\.shareLine))
        }
        if !snapshot.updatedAt.isEmpty {
            lines.append("")
            lines.append("Updated: \(snapshot.updatedAt)")
        }
        return lines.joined(separator: "\n")
    }

    func refresh(from connectionManager: ConnectionManager) async {
        guard connectionManager.isCryptoChatReady else { return }
        if connectionManager.isPipeBusyForSideTraffic { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let payload = try await connectionManager.fetchBeneficiarySnapshot()
            try apply(payload: payload)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setFamilyBeneficiary(firstName: String, connectionManager: ConnectionManager) async -> Bool {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Enter a first name."
            return false
        }
        let previous = snapshot
        applyLocalName(trimmed)
        lastError = nil

        guard connectionManager.isCryptoChatReady else {
            lastError = "Saved on this phone. Connect to your Brain in You to sync."
            return true
        }

        let idle = await waitUntilPipeIdle(connectionManager)
        guard idle, connectionManager.isCryptoChatReady else {
            lastError = nil
            Task { await self.syncFamilyNameWhenIdle(trimmed, connectionManager: connectionManager) }
            return true
        }

        do {
            let payload = try await connectionManager.setFamilyBeneficiary(firstName: trimmed)
            do {
                try apply(payload: payload)
            } catch {
                applyLocalName(trimmed)
            }
            lastError = nil
            return true
        } catch let ConnectionError.serverRejected(message) {
            snapshot = previous
            persistSnapshot()
            lastError = message
            return false
        } catch {
            lastError = nil
            Task { await self.syncFamilyNameWhenIdle(trimmed, connectionManager: connectionManager) }
            return true
        }
    }

    func submitColleague(
        name: String,
        email: String,
        phone: String,
        nonFamilyAttested: Bool,
        connectionManager: ConnectionManager
    ) async -> Bool {
        guard nonFamilyAttested else {
            lastError = "Confirm this is a colleague, not a family member."
            return false
        }
        guard connectionManager.isCryptoChatReady else {
            lastError = "Connect to your Brain in You to send referrals."
            return false
        }
        do {
            let payload = try await connectionManager.submitColleagueReferral(
                name: name,
                email: email,
                phone: phone,
                nonFamilyAttested: nonFamilyAttested
            )
            try apply(payload: payload)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func dismissRewardCelebration() {
        showRewardCelebration = false
        lastRewardedName = nil
    }

    // MARK: - Private

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? apply(payload: object)
    }

    private func apply(payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(BeneficiarySnapshot.self, from: data)

        let earnedNow = decoded.lifetimeFamilyCenturionsEarned > snapshot.lifetimeFamilyCenturionsEarned
        if earnedNow, let last = decoded.history.last {
            lastRewardedName = last.familyBeneficiaryFirstName
            showRewardCelebration = true
        } else if decoded.currentCycle.rewardReady,
                  successfulCount >= referralsRequired,
                  previousSuccessfulCount < referralsRequired {
            lastRewardedName = decoded.currentCycle.familyBeneficiaryFirstName
            showRewardCelebration = true
        }

        snapshot = decoded
        previousSuccessfulCount = decoded.currentCycle.successfulColleagueCount
        persistSnapshotData(data)
    }

    private func applyLocalName(_ name: String) {
        snapshot.currentCycle.familyBeneficiaryFirstName = name
        persistSnapshot()
    }

    private func persistSnapshot() {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(snapshot) else { return }
        persistSnapshotData(data)
    }

    private func persistSnapshotData(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func waitUntilPipeIdle(_ connectionManager: ConnectionManager) async -> Bool {
        for _ in 0..<60 {
            if !connectionManager.isPipeBusyForSideTraffic {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return !connectionManager.isPipeBusyForSideTraffic
    }

    private func syncFamilyNameWhenIdle(_ name: String, connectionManager: ConnectionManager) async {
        _ = await waitUntilPipeIdle(connectionManager)
        guard connectionManager.isCryptoChatReady else { return }
        do {
            let payload = try await connectionManager.setFamilyBeneficiary(firstName: name)
            try apply(payload: payload)
            lastError = nil
        } catch {
            // Keep the local name. Next You refresh or save retries.
        }
    }
}
