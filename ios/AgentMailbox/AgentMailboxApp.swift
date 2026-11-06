import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct AgentMailboxApp: App {
    @StateObject private var mailbox: MailboxCenter
    @StateObject private var language: LanguageStore

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MailboxAppDelegate.self) private var appDelegate
    #endif

    init() {
        let mailbox = MailboxCenter()
        _mailbox = StateObject(wrappedValue: mailbox)
        _language = StateObject(wrappedValue: LanguageStore())
        mailbox.start()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(mailbox)
                .environmentObject(language)
                .onAppear { mailbox.start() }
        }
        #if os(macOS)
        .defaultSize(width: 920, height: 680)
        #endif

        #if os(macOS)
        MenuBarExtra {
            MenuBarCommands(mailbox: mailbox, language: language)
        } label: {
            MenuBarHatLabel(mailbox: mailbox)
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}

#if os(macOS)
final class MailboxAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Keep the main window at its original default within this display.
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }),
                  let screen = window.screen ?? NSScreen.main else { return }
            let available = screen.visibleFrame
            var frame = window.frame
            frame.size.width = min(920, available.width)
            frame.size.height = min(frame.height, available.height)
            frame.origin.x = available.midX - frame.width / 2
            frame.origin.y = min(max(frame.origin.y, available.minY), available.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
}

struct MenuBarHatLabel: View {
    @ObservedObject var mailbox: MailboxCenter

    var body: some View {
        Image(nsImage: MenuBarHat.image(listening: mailbox.isListening))
            .renderingMode(.template)
            .accessibilityLabel(mailbox.isListening ? "Agent Mailbox" : "Agent Mailbox, not listening")
    }
}

struct MenuBarCommands: View {
    @ObservedObject var mailbox: MailboxCenter
    @ObservedObject var language: LanguageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(language.text(.openMainWindow)) {
            openMainWindow()
        }
        Text(L10n.status(mailbox.listenState, language.current, port: MailboxCenter.port))
        Divider()
        Button(mailbox.phase == .paused ? language.text(.resume) : language.text(.pause)) {
            mailbox.togglePause()
        }
        .disabled(!mailbox.sessionActive || mailbox.phase == .reporting)
        Button(mailbox.phase == .reporting ? language.text(.skipReports) : language.text(.endSession)) {
            mailbox.endSession()
        }
        .disabled(!mailbox.sessionActive)
        Divider()
        Picker(language.text(.language), selection: $language.current) {
            ForEach(AppLanguage.allCases) { item in
                Text(item.nativeName).tag(item)
            }
        }
        Divider()
        Button(language.text(.quit)) {
            NSApp.terminate(nil)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: "main")
    }
}

enum MenuBarHat {
    static func image(listening: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.addPath(WizardHatMark().path(in: CGRect(origin: .zero, size: size)).cgPath)
            if listening {
                context.drawPath(using: .eoFill)
            } else {
                context.setLineWidth(1)
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

#endif
