import Foundation

enum ColleagueReferralStatus: String, Codable {
    case pending
    case successful

    var displayLabel: String {
        switch self {
        case .pending: return "Pending — awaiting purchase"
        case .successful: return "Purchased — counted"
        }
    }
}

struct ColleagueReferral: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var email: String
    var phone: String
    var kind: String
    var nonFamilyAttested: Bool
    var status: ColleagueReferralStatus
    var createdAt: String

    var contactSummary: String {
        if !email.isEmpty && !phone.isEmpty {
            return "\(email) · \(phone)"
        }
        if !email.isEmpty { return email }
        if !phone.isEmpty { return phone }
        return "No contact details"
    }
}

struct BeneficiaryCycle: Codable, Equatable {
    var familyBeneficiaryFirstName: String
    var colleagueReferrals: [ColleagueReferral]
    var successfulColleagueCount: Int
    var progressRemaining: Int
    var rewardReady: Bool

    static let empty = BeneficiaryCycle(
        familyBeneficiaryFirstName: "",
        colleagueReferrals: [],
        successfulColleagueCount: 0,
        progressRemaining: 4,
        rewardReady: false
    )
}

struct BeneficiaryHistoryCycle: Codable, Equatable, Identifiable {
    let id: String
    var familyBeneficiaryFirstName: String
    var colleagueReferrals: [ColleagueReferral]
    var completedAt: String
}

struct BeneficiarySnapshot: Codable, Equatable {
    var ok: Bool
    var referralsRequired: Int
    var currentCycle: BeneficiaryCycle
    var lifetimeFamilyCenturionsEarned: Int
    var history: [BeneficiaryHistoryCycle]
    var updatedAt: String

    static let empty = BeneficiarySnapshot(
        ok: true,
        referralsRequired: 4,
        currentCycle: .empty,
        lifetimeFamilyCenturionsEarned: 0,
        history: [],
        updatedAt: ""
    )
}
