import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mailbox: MailboxCenter
    @EnvironmentObject private var language: LanguageStore

    @State private var interruption = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.status(mailbox.listenState, language.current, port: MailboxCenter.port))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                DisclosureGroup(language.text(.startSection)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(language.text(.firstAgent), text: $mailbox.agentA).disabled(mailbox.sessionActive)
                        TextField(language.text(.otherAgent), text: $mailbox.agentB).disabled(mailbox.sessionActive)
                        TextField(language.text(.sharedTask), text: $mailbox.topic, axis: .vertical).disabled(mailbox.sessionActive)
                        Stepper(value: $mailbox.rounds, in: 1...20) {
                            Text(L10n.rounds(mailbox.rounds, language.current))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .disabled(mailbox.sessionActive)
                        Button(language.text(.startNew)) { mailbox.begin(language: language.current) }
                            .disabled(!mailbox.canStart || !mailbox.isListening || mailbox.sessionActive)
                        Text(progressLine)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(mailbox.phase == .paused ? language.text(.resume) : language.text(.pause)) { mailbox.togglePause() }
                                .disabled(!mailbox.sessionActive || mailbox.phase == .reporting)
                            Button(mailbox.phase == .reporting ? language.text(.skipReports) : language.text(.endSession)) { mailbox.endSession() }
                                .disabled(!mailbox.sessionActive)
                        }
                        TextField(language.text(.userNote), text: $interruption)
                        Button(language.text(.sendNote)) {
                            mailbox.interject(interruption, language: language.current)
                            interruption = ""
                        }
                        ShareLink(L10n.instructionsTitle(mailbox.agentA, language.current), item: mailbox.instructions(for: mailbox.agentA, language: language.current))
                        ShareLink(L10n.instructionsTitle(mailbox.agentB, language.current), item: mailbox.instructions(for: mailbox.agentB, language: language.current))
                        Text(language.text(.instructionsHint))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        languagePicker
                        Text(language.text(.languageNote))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        let notice = L10n.notice(mailbox.notice, language.current)
                        if !notice.isEmpty {
                            Text(notice)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.textFieldStyle(.roundedBorder)
                }.padding(.horizontal, 16)
                GeometryReader { proxy in
                    let sideBySide = proxy.size.width > 700
                    let stack = sideBySide ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
                    stack {
                        ForEach(slots) { slot in
                            TypingCard(slot: slot)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(Color.mailboxBackground)
            .navigationTitle(language.text(.appTitle))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(language.text(.viewConversation)) {
                            mailbox.conversationOpen = true
                            mailbox.markConversationRead()
                        }
                    } label: {
                        conversationLabel
                    }
                    .accessibilityLabel(L10n.unreadLabel(count: mailbox.unread, language: language.current))
                }
            }
            .sheet(isPresented: conversationBinding) {
                ConversationSheet()
                    .environmentObject(mailbox)
                    .environmentObject(language)
                    #if os(macOS)
                    .frame(width: 1024, height: 680)
                    #endif
            }
        }
    }

    private var progressLine: String {
        if mailbox.phase == .reporting {
            return L10n.reportingStatus(mailbox.pendingReports, language.current)
        }
        return L10n.progress(phase: mailbox.phase, replies: mailbox.completedReplies, next: mailbox.expected, language: language.current)
    }

    private var languagePicker: some View {
        Picker(language.text(.language), selection: $language.current) {
            ForEach(AppLanguage.allCases) { item in
                Text(item.nativeName).tag(item)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(language.text(.language))
    }

    private var conversationBinding: Binding<Bool> {
        Binding(
            get: { mailbox.conversationOpen },
            set: { isOpen in
                mailbox.conversationOpen = isOpen
                if !isOpen {
                    mailbox.markConversationRead()
                }
            }
        )
    }

    private var menuImage: some View {
        WizardHatMark()
            .fill(mailbox.isListening ? Color.primary : Color.primary.opacity(0.35), style: FillStyle(eoFill: true))
    }

    private var conversationLabel: some View {
        ZStack(alignment: .topTrailing) {
            menuImage
                .frame(width: 28, height: 18)
            if mailbox.unread > 0 {
                Text(mailbox.unread > 9 ? "9+" : "\(mailbox.unread)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
                    .offset(x: 10, y: -8)
            }
        }
        .frame(width: 36, height: 28)
    }

    private var slots: [TypingSlot] {
        let names = visibleNames
        if names.isEmpty {
            return [
                TypingSlot(id: 0, title: language.text(.waitingFirst), text: language.text(.nobodyWrote), filled: false, readingText: ""),
                TypingSlot(id: 1, title: language.text(.waitingSecond), text: language.text(.nobodyWrote), filled: false, readingText: "")
            ]
        }
        var result = names.prefix(2).enumerated().map { index, name in
            let panel = mailbox.panels[name] ?? ""
            let isReading = mailbox.reading.contains(name)
            let wrote = mailbox.order.contains(name)
            return TypingSlot(
                id: index,
                title: L10n.displayName(name, language.current),
                text: panel.isEmpty && !isReading && !wrote ? language.text(.nobodyWrote) : panel,
                filled: wrote,
                readingText: isReading ? L10n.readingStatus(name, language.current) : ""
            )
        }
        if result.count == 1 {
            result.append(TypingSlot(id: 1, title: language.text(.waitingSecond), text: language.text(.nobodyWrote), filled: false, readingText: ""))
        }
        return result
    }

    private var visibleNames: [String] {
        if mailbox.sessionActive {
            return [mailbox.agentA, mailbox.agentB]
        }
        var names = mailbox.order
        for name in mailbox.reading where !names.contains(name) {
            names.append(name)
        }
        return names
    }
}

/// Shared silhouette for the window menu and the macOS menu bar.
struct WizardHatMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 71))
        path.addCurve(to: CGPoint(x: 48, y: 13), control1: CGPoint(x: 35, y: 49), control2: CGPoint(x: 31, y: 22))
        path.addCurve(to: CGPoint(x: 79, y: 10), control1: CGPoint(x: 59, y: 4), control2: CGPoint(x: 72, y: 3))
        path.addCurve(to: CGPoint(x: 88, y: 34), control1: CGPoint(x: 86, y: 17), control2: CGPoint(x: 89, y: 27))
        path.addCurve(to: CGPoint(x: 72, y: 24), control1: CGPoint(x: 83, y: 33), control2: CGPoint(x: 79, y: 19))
        path.addCurve(to: CGPoint(x: 69, y: 48), control1: CGPoint(x: 62, y: 25), control2: CGPoint(x: 65, y: 39))
        path.addLine(to: CGPoint(x: 82, y: 73))
        path.addCurve(to: CGPoint(x: 98, y: 85), control1: CGPoint(x: 93, y: 76), control2: CGPoint(x: 98, y: 80))
        path.addCurve(to: CGPoint(x: 3, y: 85), control1: CGPoint(x: 96, y: 100), control2: CGPoint(x: 4, y: 100))
        path.addCurve(to: CGPoint(x: 24, y: 71), control1: CGPoint(x: 0, y: 79), control2: CGPoint(x: 13, y: 73))
        path.closeSubpath()
        // Large J cutout, shared by the window menu and template menu-bar icon.
        path.move(to: CGPoint(x: 55, y: 43))
        path.addLines([CGPoint(x: 73, y: 43), CGPoint(x: 73, y: 49), CGPoint(x: 69, y: 49), CGPoint(x: 69, y: 65)])
        path.addCurve(to: CGPoint(x: 55, y: 79), control1: CGPoint(x: 69, y: 75), control2: CGPoint(x: 64, y: 79))
        path.addCurve(to: CGPoint(x: 42, y: 66), control1: CGPoint(x: 46, y: 79), control2: CGPoint(x: 41, y: 74))
        path.addLine(to: CGPoint(x: 50, y: 64))
        path.addCurve(to: CGPoint(x: 55, y: 71), control1: CGPoint(x: 49, y: 69), control2: CGPoint(x: 51, y: 71))
        path.addCurve(to: CGPoint(x: 61, y: 65), control1: CGPoint(x: 59, y: 71), control2: CGPoint(x: 61, y: 69))
        path.addLines([CGPoint(x: 61, y: 49), CGPoint(x: 55, y: 49)])
        path.closeSubpath()
        let side = min(rect.width, rect.height)
        return path.applying(CGAffineTransform(scaleX: side / 100, y: side / 100)
            .concatenating(CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)))
    }
}

private struct TypingSlot: Identifiable {
    var id: Int
    var title: String
    var text: String
    var filled: Bool
    var readingText: String
}

private struct TypingCard: View {
    let slot: TypingSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(slot.readingText.isEmpty ? (slot.filled ? Color.green : Color.secondary.opacity(0.4)) : Color.orange)
                    .frame(width: 8, height: 8)
                Text(slot.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            if !slot.readingText.isEmpty {
                Text(slot.readingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                Text(slot.text.isEmpty ? " " : slot.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(slot.filled ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mailboxCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ConversationSheet: View {
    @EnvironmentObject private var mailbox: MailboxCenter
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if mailbox.turns.isEmpty {
                    ContentUnavailableView(
                        language.text(.noConversation),
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(language.text(.noConversationDetail))
                    )
                } else if roundGroups.isEmpty && reportTurns.isEmpty && !showReportPlaceholder {
                    ContentUnavailableView(
                        language.text(.noMatches),
                        systemImage: "magnifyingglass",
                        description: Text(query)
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(roundGroups, id: \.round) { group in
                                RoundDivider(title: L10n.roundTitle(group.round, language.current))
                                ForEach(group.turns) { turn in
                                    turnCard(turn)
                                }
                            }
                            if showReportPlaceholder || !reportTurns.isEmpty {
                                RoundDivider(title: language.text(.reportsHeader))
                                if reportTurns.isEmpty {
                                    Text(language.text(.reportsWaiting))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                ForEach(reportTurns) { turn in
                                    turnCard(turn)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .searchable(text: $query, prompt: Text(language.text(.searchPlaceholder)))
            .navigationTitle(language.text(.conversationTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text(.close)) { dismiss() }
                }
            }
        }
    }

    private var keyword: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleTurns: [DialogueTurn] {
        mailbox.turns.filter {
            ConversationSearch.matches(sender: $0.sender, recipient: $0.recipient, text: $0.text, query: keyword)
        }
    }

    private var roundGroups: [(round: Int, turns: [DialogueTurn])] {
        let messages = visibleTurns.filter { !$0.isReport }
        let rounds = Array(Set(messages.map(\.round))).sorted()
        return rounds.map { round in
            (round, messages.filter { $0.round == round })
        }
    }

    private var reportTurns: [DialogueTurn] {
        visibleTurns.filter(\.isReport)
    }

    private var showReportPlaceholder: Bool {
        keyword.isEmpty && mailbox.phase == .reporting && reportTurns.isEmpty
    }

    private func turnCard(_ turn: DialogueTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(L10n.displayName(turn.sender, language.current)) → \(L10n.displayName(turn.recipient, language.current))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            highlighted(turn.text.isEmpty ? language.text(.emptyBody) : turn.text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mailboxCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func highlighted(_ source: String) -> Text {
        let needle = keyword
        guard !needle.isEmpty else { return Text(source) }
        var attributed = AttributedString(source)
        var searchFrom = source.startIndex
        while let range = source.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchFrom..<source.endIndex) {
            if let start = AttributedString.Index(range.lowerBound, within: attributed),
               let end = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[start..<end].inlinePresentationIntent = .stronglyEmphasized
                attributed[start..<end].backgroundColor = .yellow
            }
            searchFrom = range.upperBound
            if searchFrom == source.endIndex { break }
        }
        return Text(attributed)
    }
}

private struct RoundDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            line
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
        .accessibilityAddTraits(.isHeader)
        .padding(.top, 4)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.45))
            .frame(height: 1)
    }
}

private extension Color {
    static var mailboxBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }
    static var mailboxCard: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }
}
