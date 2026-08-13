import SwiftUI

/// Memory Horizon showcase — three layers with live fill gauges and per-layer guidance.
struct MemoryHorizonView: View {
    @EnvironmentObject private var memoryHorizonStore: MemoryHorizonStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedLayer: MemoryHorizonLayer?
    @State private var chatTarget: ChatSheetTarget?

    private var linked: Bool {
        connectionManager.isCryptoChatReady
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                header

                if !linked {
                    offlineBanner
                }

                ForEach(MemoryHorizonLayer.allCases) { layer in
                    layerCard(layer)
                }

                learnMore
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .navigationTitle("Memory Horizon")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await memoryHorizonStore.refresh(from: connectionManager)
        }
        .sheet(item: $selectedLayer) { layer in
            NavigationStack {
                layerDetail(layer)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { selectedLayer = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $chatTarget) { target in
            let conversation = messageService.findOrCreateConversation(for: target.context)
            NavigationStack {
                ChatView(conversation: conversation, usesPageChrome: false)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { chatTarget = nil }
                        }
                    }
            }
            .presentationDetents([.height(380), .large])
        }
    }

    private var header: some View {
        AtmosphericSurface(elevated: true, showRim: true) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CenturionSectionHeader(title: "How it remembers", icon: "circle.hexagongrid")

                Text("Memory Horizon")
                    .font(Typography.editorialTitle)
                    .foregroundColor(ColorTheme.primaryText())

                Text("Three layers on your Sovereign — a small always-on card, searchable conversation history, and optional sealed long-term notes. Hot Cache is a software budget; Session Recall and Vault grow with use and share disk on your Sovereign.")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundColor(ColorTheme.accent())
            Text("Link your Sovereign to see live memory levels.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(ColorTheme.accent().opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func layerCard(_ layer: MemoryHorizonLayer) -> some View {
        Button {
            Haptics.lightTap()
            selectedLayer = layer
        } label: {
            AtmosphericSurface {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: layer.icon)
                            .foregroundColor(ColorTheme.accent())
                        Text(layer.horizonLabel.uppercased())
                            .font(Typography.sectionLabel)
                            .tracking(1.2)
                            .foregroundColor(ColorTheme.accent())
                        Spacer()
                        statusChip(for: layer)
                    }

                    Text(layer.title)
                        .font(.headline)
                        .foregroundColor(ColorTheme.primaryText())

                    Text(layer.blurb)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .fixedSize(horizontal: false, vertical: true)

                    HorizonFillBar(ratio: fillRatio(for: layer), muted: isMuted(layer))

                    Text(metricLine(for: layer))
                        .font(.caption2.monospaced())
                        .foregroundColor(ColorTheme.dimAccent())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(layer.title), \(statusLabel(for: layer))")
    }

    private func layerDetail(_ layer: MemoryHorizonLayer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                AtmosphericSurface(elevated: true) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("\(layer.horizonLabel) · \(layer.title)")
                            .font(Typography.editorialTitle)
                            .foregroundColor(ColorTheme.primaryText())
                        Text(layer.blurb)
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                        HorizonFillBar(ratio: fillRatio(for: layer), muted: isMuted(layer))
                        Text(metricLine(for: layer))
                            .font(.caption.monospaced())
                            .foregroundColor(ColorTheme.dimAccent())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    CenturionSectionHeader(title: "How to grow or manage", icon: "lightbulb")
                    Text(guidanceCopy(for: layer))
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Haptics.mediumTap()
                    selectedLayer = nil
                    openChat(for: layer)
                } label: {
                    Text(primaryActionTitle(for: layer))
                }
                .buttonStyle(CenturionPrimaryButtonStyle())
                .disabled(!linked)

                if !linked {
                    Text("Link your Sovereign first to take this action.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                }
            }
            .padding()
        }
        .background(ColorTheme.background())
        .navigationTitle(layer.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var learnMore: some View {
        Button {
            UIApplication.shared.open(CenturionHelp.memoryHorizon)
        } label: {
            CenturionListRow(
                icon: "book.pages",
                title: "Learn more",
                subtitle: "Memory Horizon in the Help Center"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metrics

    private func fillRatio(for layer: MemoryHorizonLayer) -> Double {
        switch layer {
        case .hotCache: return memoryHorizonStore.snapshot.hotCache.fillRatio
        case .sessionRecall: return memoryHorizonStore.snapshot.sessionRecall.fillRatio
        case .vault: return memoryHorizonStore.snapshot.vault.fillRatio
        }
    }

    private func isMuted(_ layer: MemoryHorizonLayer) -> Bool {
        let v = memoryHorizonStore.snapshot.vault
        if layer == .vault {
            return !v.enabled || !v.initialized || (!v.unlocked && v.initialized)
        }
        return false
    }

    private func metricLine(for layer: MemoryHorizonLayer) -> String {
        let s = memoryHorizonStore.snapshot
        switch layer {
        case .hotCache:
            let h = s.hotCache
            return "\(h.usedChars)/\(h.limitChars) chars · MEMORY \(h.memoryChars)/\(h.memoryLimit) · YOU \(h.userChars)/\(h.userLimit)"
        case .sessionRecall:
            let r = s.sessionRecall
            return "\(r.sessions) conversations · \(byteString(r.dbBytes)) used · \(byteString(r.freeBytes)) free on Sovereign"
        case .vault:
            let v = s.vault
            if !v.enabled || !v.initialized {
                return "Off — not set up on your Sovereign yet"
            }
            let lock = v.unlocked ? "Unlocked" : "Locked"
            return "\(lock) · \(v.totalEntries) notes · \(byteString(v.dbBytes)) · Core \(v.counts["core"] ?? 0) · Experience \(v.counts["experiential"] ?? 0) · Pattern \(v.counts["pattern"] ?? 0)"
        }
    }

    private func statusLabel(for layer: MemoryHorizonLayer) -> String {
        switch layer {
        case .hotCache:
            let r = memoryHorizonStore.snapshot.hotCache.fillRatio
            if r >= 0.85 { return "Getting full" }
            return "Healthy"
        case .sessionRecall:
            let r = memoryHorizonStore.snapshot.sessionRecall.fillRatio
            if r >= 0.85 { return "Disk getting full" }
            return "Growing"
        case .vault:
            let v = memoryHorizonStore.snapshot.vault
            if !v.enabled || !v.initialized { return "Off" }
            if !v.unlocked { return "Locked" }
            if v.fillRatio >= 0.85 { return "Disk getting full" }
            return "Ready"
        }
    }

    private func statusChip(for layer: MemoryHorizonLayer) -> some View {
        let label = statusLabel(for: layer)
        return Text(label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(ColorTheme.accent())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ColorTheme.accent().opacity(0.12))
            .clipShape(Capsule())
    }

    private func guidanceCopy(for layer: MemoryHorizonLayer) -> String {
        switch layer {
        case .hotCache:
            return "Fullness is the wallet-card budget (not hardware). To make room, ask your Centurion to remove stale facts or tighten essentials. Raising the char limit is an advanced config change on the brain — not a product upgrade."
        case .sessionRecall:
            return "Grows automatically as you chat. Richer recall means more history. Limited only by disk on your Sovereign. If disk is getting full, ask your Centurion about pruning older sessions."
        case .vault:
            return "Far horizon for sealed long-term notes. Grow by proposing durable facts (not dumping chats). Set up and unlock Vault on your Sovereign computer; the passphrase stays there."
        }
    }

    private func primaryActionTitle(for layer: MemoryHorizonLayer) -> String {
        switch layer {
        case .hotCache:
            return "Ask to curate Hot Cache"
        case .sessionRecall:
            let high = memoryHorizonStore.snapshot.sessionRecall.fillRatio >= 0.85
            return high ? "Ask about pruning old sessions" : "Ask what you remember recently"
        case .vault:
            let v = memoryHorizonStore.snapshot.vault
            if !v.enabled || !v.initialized {
                return "Ask how to turn on Vault"
            }
            if !v.unlocked {
                return "Ask how to unlock Vault"
            }
            return "Propose a durable Vault note"
        }
    }

    private func openChat(for layer: MemoryHorizonLayer) {
        let prompt: String
        switch layer {
        case .hotCache:
            prompt = "Help me curate Hot Cache — keep what matters, free space for new essentials."
        case .sessionRecall:
            if memoryHorizonStore.snapshot.sessionRecall.fillRatio >= 0.85 {
                prompt = "Disk for Session Recall is getting full on this Sovereign. Help me prune or archive older sessions safely."
            } else {
                prompt = "Summarize what you remember from recent sessions that still matters."
            }
        case .vault:
            let v = memoryHorizonStore.snapshot.vault
            if !v.enabled || !v.initialized {
                prompt = "Walk me through turning on Vault on this Sovereign (init, enable, unlock). Keep the passphrase on the computer."
            } else if !v.unlocked {
                prompt = "Vault is locked. Tell me how to unlock it on this Sovereign so we can store durable notes."
            } else {
                prompt = "Propose a durable fact for Vault — something worth sealing long-term, not a full chat transcript."
            }
        }
        let conversation = messageService.seedDiscussContext(
            title: "Memory Horizon · \(layer.title)",
            detail: prompt
        )
        NotificationCenter.default.post(name: .centurionSelectTab, object: 0)
        chatTarget = ChatSheetTarget(context: conversation.context)
    }

    private func byteString(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Calm fill bar for Memory Horizon layers.
struct HorizonFillBar: View {
    let ratio: Double
    var muted: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.border().opacity(0.5))
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorTheme.accent().opacity(muted ? 0.25 : 0.85))
                    .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, ratio)))))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Fill \(Int((ratio * 100).rounded())) percent")
    }
}

extension MemoryHorizonLayer: Hashable {}
