import SwiftUI

/// Sales hero for the You tab (pillars + privacy compare).
struct CenturionShowcaseSection: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var showPrivacyTrust = false

    var body: some View {
        differenceStory
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
    }
}

/// Family & friends referral tracker — always visible on the You tab.
struct FamilyFriendsReferralSection: View {
    @EnvironmentObject private var beneficiaryStore: BeneficiaryStore
    @EnvironmentObject private var connectionManager: ConnectionManager

    @State private var showNominateSheet = false
    @State private var showAddColleagueSheet = false

    var body: some View {
        FamilyBeneficiaryCard(
            onNominate: { showNominateSheet = true },
            onReferColleague: { showAddColleagueSheet = true }
        )
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
    @EnvironmentObject private var connectionManager: ConnectionManager

    let onNominate: () -> Void
    let onReferColleague: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                CenturionSectionHeader(title: "Family & friends referrals", icon: "gift")
                Spacer(minLength: 0)
                if connectionManager.isCryptoChatReady {
                    Button {
                        Task { await beneficiaryStore.refresh(from: connectionManager) }
                    } label: {
                        if beneficiaryStore.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body.weight(.medium))
                                .foregroundColor(ColorTheme.accent())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(beneficiaryStore.isRefreshing)
                    .accessibilityLabel("Refresh referral status")
                    .accessibilityHint("Checks your Sovereign for new customer purchases")
                }
            }

            AtmosphericSurface(showRim: true) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Nominate one family member you are earning for. Refer friends or colleagues with name, email, and phone — they stay on this tracker so you can see who became a customer and get credit toward four purchases for one complimentary Sovereign.")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(4)

                    if !connectionManager.isCryptoChatReady {
                        Text("Link your Sovereign above to save referrals and sync status.")
                            .font(.caption.weight(.medium))
                            .foregroundColor(ColorTheme.accent())
                    }

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

                    referralTrackerHeader
                    colleagueList

                    actionButtons
                }
            }

            Text("Refer friends and colleagues — not family members on this list. Waiting means referred; Customer means their purchase credited your fee machine. When you earn a complimentary Sovereign, our team will be in touch — this app does not provision hardware automatically.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
                .padding(.horizontal, Spacing.xs)
                .lineSpacing(2)
        }
    }

    @ViewBuilder
    private var referralTrackerHeader: some View {
        HStack {
            Text("People you’ve referred")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.primaryText())
            Spacer(minLength: 0)
            if !beneficiaryStore.colleagueReferrals.isEmpty {
                ShareLink(item: beneficiaryStore.referralShareText) {
                    Label("Share list", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                        .foregroundColor(ColorTheme.accent())
                }
                .accessibilityHint("Share the names and customer status of your referrals")
            }
        }
    }

    @ViewBuilder
    private var beneficiaryGoalBlock: some View {
        if beneficiaryStore.hasBeneficiary {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Earning a Sovereign for \(beneficiaryStore.beneficiaryFirstName)")
                    .font(.body.weight(.semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("\(beneficiaryStore.successfulCount) of \(beneficiaryStore.referralsRequired) customer purchases credited")
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
            Text("No referrals yet. Add a friend or colleague to start tracking.")
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
            .disabled(!connectionManager.isCryptoChatReady)
        } else {
            Button(action: onReferColleague) {
                Text("Refer a friend or colleague")
            }
            .buttonStyle(CenturionPrimaryButtonStyle())
            .disabled(
                !connectionManager.isCryptoChatReady
                    || beneficiaryStore.successfulCount >= beneficiaryStore.referralsRequired
            )

            Button(action: onNominate) {
                Text("Change beneficiary")
            }
            .buttonStyle(CenturionGhostButtonStyle())
            .disabled(!beneficiaryStore.colleagueReferrals.isEmpty || !connectionManager.isCryptoChatReady)
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
        .accessibilityLabel("Progress: \(successful) of \(required) customer purchases credited")
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
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(referral.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText())
                    Spacer(minLength: 0)
                    Text(referral.status.shortLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(referral.status == .successful ? ColorTheme.success() : ColorTheme.mutedText())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    referral.status == .successful
                                        ? ColorTheme.success().opacity(0.15)
                                        : ColorTheme.border().opacity(0.5)
                                )
                        )
                }
                Text(referral.contactSummary)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                Text(referral.status.displayLabel)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(referral.name), \(referral.status.displayLabel), \(referral.contactSummary)")
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
    @State private var showContactPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SheetHeader(
                        title: "Refer a friend or colleague",
                        subtitle: "Capture name, email, and phone. They appear on your tracker so you can see when they become a customer."
                    )

                    Button {
                        showContactPicker = true
                    } label: {
                        Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                    .accessibilityHint("Pick a contact to fill name, email, and phone")

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
                        Text("This is a friend or colleague, not a family member")
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
                            Text("Add to tracker")
                        }
                    }
                    .buttonStyle(CenturionPrimaryButtonStyle())
                    .disabled(!canSubmit || isSaving)
                }
                .padding()
            }
            .background(ColorTheme.background())
            .navigationTitle("Referral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ColorTheme.accent())
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerRepresentable(
                    onPick: { pickedName, pickedEmail, pickedPhone in
                        if !pickedName.isEmpty { name = pickedName }
                        if !pickedEmail.isEmpty { email = pickedEmail }
                        if !pickedPhone.isEmpty { phone = pickedPhone }
                        showContactPicker = false
                    },
                    onCancel: { showContactPicker = false }
                )
                .ignoresSafeArea()
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
