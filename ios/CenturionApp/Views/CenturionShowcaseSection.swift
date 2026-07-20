import SwiftUI

/// Sales hero + Family Beneficiary Program for the You tab.
struct CenturionShowcaseSection: View {
    @EnvironmentObject private var beneficiaryStore: BeneficiaryStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    @State private var showNominateSheet = false
    @State private var showAddColleagueSheet = false
    @State private var showPrivacyTrust = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            differenceStory
            FamilyBeneficiaryCard(
                onNominate: { showNominateSheet = true },
                onReferColleague: { showAddColleagueSheet = true }
            )
        }
        .sheet(isPresented: $showNominateSheet) {
            NominateFamilyBeneficiarySheet()
                .environmentObject(beneficiaryStore)
                .environmentObject(connectionManager)
        }
        .sheet(isPresented: $showAddColleagueSheet) {
            AddColleagueReferralSheet()
                .environmentObject(beneficiaryStore)
                .environmentObject(connectionManager)
        }
        .alert("Sovereign earned", isPresented: $beneficiaryStore.showRewardCelebration) {
            Button("Nominate next") {
                beneficiaryStore.dismissRewardCelebration()
                showNominateSheet = true
            }
            Button("Done", role: .cancel) {
                beneficiaryStore.dismissRewardCelebration()
            }
        } message: {
            if let name = beneficiaryStore.lastRewardedName {
                Text("You've earned a complimentary Sovereign for \(name). Our team will be in touch.")
            } else {
                Text("You've earned a complimentary family Sovereign. Our team will be in touch.")
            }
        }
        .task(id: connectionManager.connectionState) {
            await beneficiaryStore.refresh(from: connectionManager)
        }
    }

    private var differenceStory: some View {
        VStack(spacing: Spacing.md) {
            Text("Your private Sovereign — on your machine, for your mission.")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text("Show a colleague why you chose Sovereign.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)

            VStack(spacing: Spacing.sm) {
                ShowcasePillar(icon: "server.rack", title: "Yours, not rented", detail: "AI runs on your Sovereign, not a cloud chatbot.")
                ShowcasePillar(icon: "target", title: "Mission-centered", detail: "Built around your life purpose, not endless tasks.")
                ShowcasePillar(icon: "lock.shield", title: "Private by design", detail: "Your network, your data, your control.")
                ShowcasePillar(icon: "iphone.and.arrow.forward", title: "Always beside you", detail: "Your phone is a calm remote — your Sovereign does the work.")
            }

            Button {
                showPrivacyTrust = true
            } label: {
                Text("How we compare to cloud AI")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open privacy and trust comparisons")
        }
        .sheet(isPresented: $showPrivacyTrust) {
            NavigationStack {
                SecurityHubView()
                    .environmentObject(connectionManager)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPrivacyTrust = false }
                                .foregroundColor(ColorTheme.accent())
                        }
                    }
            }
        }
    }
}

private struct ShowcasePillar: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        AtmosphericSurface {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundColor(ColorTheme.accent())
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Family Beneficiary Card

struct FamilyBeneficiaryCard: View {
    @EnvironmentObject private var beneficiaryStore: BeneficiaryStore

    let onNominate: () -> Void
    let onReferColleague: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: "Family Beneficiary Program", icon: "gift")

            AtmosphericSurface(showRim: true) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Introduce four colleagues who buy Sovereign — earn one for someone you love.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(4)

                    if beneficiaryStore.snapshot.lifetimeFamilyCenturionsEarned > 0 {
                        Text("\(beneficiaryStore.snapshot.lifetimeFamilyCenturionsEarned) family Sovereign\(beneficiaryStore.snapshot.lifetimeFamilyCenturionsEarned == 1 ? "" : "s") earned")
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.accent())
                    }

                    beneficiaryGoalBlock
                    ColleagueProgressBar(
                        successful: beneficiaryStore.successfulCount,
                        required: beneficiaryStore.referralsRequired
                    )

                    if let error = beneficiaryStore.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(ColorTheme.error())
                    }

                    colleagueList

                    actionButtons
                }
            }

            Text("Refer colleagues who will buy their own Sovereign. Family members are who you're earning for — they can't be counted as referrals.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .padding(.horizontal, Spacing.xs)
                .lineSpacing(2)
        }
    }

    @ViewBuilder
    private var beneficiaryGoalBlock: some View {
        if beneficiaryStore.hasBeneficiary {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Earning a Sovereign for \(beneficiaryStore.beneficiaryFirstName)")
                    .font(.body.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("\(beneficiaryStore.successfulCount) of \(beneficiaryStore.referralsRequired) colleagues")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Who in your family are you earning this for?")
                    .font(.body.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Nominate their first name to set your goal.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
    }

    @ViewBuilder
    private var colleagueList: some View {
        if beneficiaryStore.colleagueReferrals.isEmpty {
            Text("No colleague referrals yet.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(beneficiaryStore.colleagueReferrals) { referral in
                    ColleagueReferralRow(referral: referral)
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if !beneficiaryStore.hasBeneficiary {
            Button(action: onNominate) {
                Text("Nominate family beneficiary")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
        } else {
            Button(action: onReferColleague) {
                Text("Refer a colleague")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .disabled(beneficiaryStore.successfulCount >= beneficiaryStore.referralsRequired)

            Button(action: onNominate) {
                Text("Change beneficiary")
            }
            .buttonStyle(CenturionGhostButtonStyle())
            .disabled(!beneficiaryStore.colleagueReferrals.isEmpty)
        }
    }
}

struct ColleagueProgressBar: View {
    let successful: Int
    let required: Int

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<required, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(index < successful ? ColorTheme.accent() : ColorTheme.border())
                    .frame(height: 8)
            }
        }
        .accessibilityLabel("Progress: \(successful) of \(required) successful colleague referrals")
    }
}

struct ColleagueReferralRow: View {
    let referral: ColleagueReferral

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: referral.status == .successful ? "checkmark.circle.fill" : "clock")
                .foregroundColor(referral.status == .successful ? ColorTheme.success() : ColorTheme.mutedText())
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(referral.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ColorTheme.primaryText())
                Text(referral.contactSummary)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                Text(referral.status.displayLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(referral.status == .successful ? ColorTheme.success() : ColorTheme.mutedText())
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Sheets

struct NominateFamilyBeneficiarySheet: View {
    @EnvironmentObject private var beneficiaryStore: BeneficiaryStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                SheetHeader(
                    title: "Family beneficiary",
                    subtitle: "Who in your family are you earning a complimentary Sovereign for? First name only."
                )

                TextField("First name", text: $firstName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()

                Button {
                    Task {
                        isSaving = true
                        let ok = await beneficiaryStore.setFamilyBeneficiary(
                            firstName: firstName,
                            connectionManager: connectionManager
                        )
                        isSaving = false
                        if ok { dismiss() }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save goal")
                    }
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                Spacer()
            }
            .padding()
            .background(ColorTheme.background())
            .navigationTitle("Nominate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
            .onAppear {
                firstName = beneficiaryStore.beneficiaryFirstName
            }
        }
    }
}

struct AddColleagueReferralSheet: View {
    @EnvironmentObject private var beneficiaryStore: BeneficiaryStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var nonFamilyAttested = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Refer a colleague",
                        subtitle: "A business contact who may buy their own Sovereign — not a family member."
                    )

                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone", text: $phone)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)

                    Toggle(isOn: $nonFamilyAttested) {
                        Text("This is a colleague or business contact, not a family member")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.primaryText())
                    }
                    .tint(ColorTheme.accent())

                    Button {
                        Task {
                            isSaving = true
                            let ok = await beneficiaryStore.submitColleague(
                                name: name,
                                email: email,
                                phone: phone,
                                nonFamilyAttested: nonFamilyAttested,
                                connectionManager: connectionManager
                            )
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Submit referral")
                        }
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .disabled(!canSubmit || isSaving)
                }
                .padding()
            }
            .background(ColorTheme.background())
            .navigationTitle("Colleague")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
    }

    private var canSubmit: Bool {
        nonFamilyAttested
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
