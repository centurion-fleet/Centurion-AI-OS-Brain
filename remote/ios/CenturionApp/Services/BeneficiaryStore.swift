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
        guard connectionManager.isCryptoChatReady else {
            lastError = "Link your Sovereign in You to save this."
            return false
        }
        do {
            let payload = try await connectionManager.setFamilyBeneficiary(firstName: trimmed)
            try apply(payload: payload)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
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
            lastError = "Link your Sovereign in You to send referrals."
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
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
