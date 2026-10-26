import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mailbox: MailboxCenter

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(mailbox.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("两个智能体")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("查看两人对话") {
                            mailbox.conversationOpen = true
                            mailbox.markConversationRead()
                        }
                    } label: {
                        conversationLabel
                    }
                    .accessibilityLabel(mailbox.unread > 0 ? "对话，\(mailbox.unread) 条新内容" : "对话")
                }
            }
            .sheet(isPresented: conversationBinding) {
                ConversationSheet()
                    .environmentObject(mailbox)
            }
        }
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

    private var conversationLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image("FedoraIndicator")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 18)
                .foregroundStyle(mailbox.isListening ? Color.black : Color.white)
                .padding(mailbox.isListening ? 0 : 6)
                .background(mailbox.isListening ? Color.clear : Color.black, in: Circle())
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
        if mailbox.order.isEmpty {
            return [
                TypingSlot(title: "等待第一位", text: "还没有人写字。", filled: false),
                TypingSlot(title: "等待第二位", text: "还没有人写字。", filled: false)
            ]
        }
        var result = mailbox.order.prefix(2).map { name in
            TypingSlot(title: name, text: mailbox.panels[name] ?? "", filled: true)
        }
        if result.count == 1 {
            result.append(TypingSlot(title: "等待第二位", text: "还没有人写字。", filled: false))
        }
        return result
    }
}

private struct TypingSlot: Identifiable {
    var title: String
    var text: String
    var filled: Bool
    var id: String { title }
}

private struct TypingCard: View {
    let slot: TypingSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(slot.filled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(slot.title)
                    .font(.headline)
                Spacer()
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ConversationSheet: View {
    @EnvironmentObject private var mailbox: MailboxCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if mailbox.turns.isEmpty {
                    ContentUnavailableView("还没有对话", systemImage: "bubble.left.and.bubble.right", description: Text("一位智能体写完并放上 <<<END>>> 之后，会出现在这里。"))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(mailbox.turns) { turn in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(turn.sender) → \(turn.recipient)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(turn.text.isEmpty ? "（空）" : turn.text)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("两人对话")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
