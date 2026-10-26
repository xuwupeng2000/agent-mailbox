import SwiftUI

@main
struct AgentMailboxApp: App {
    @StateObject private var mailbox = MailboxCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mailbox)
                .onAppear { mailbox.start() }
        }
    }
}
