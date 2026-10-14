//
//  VerificationMailManager.swift
//  boringNotch
//
//  Watches Apple Mail's inbox for verification codes / magic links and surfaces
//  them in the notch. Mail is polled over Apple Events only while Mail.app is
//  already running, so we never launch it on the user's behalf.
//

import AppKit
import Combine
import Defaults
import Foundation

extension Notification.Name {
    static let verificationAlertArrived = Notification.Name("verificationAlertArrived")
    static let verificationAlertDismissed = Notification.Name("verificationAlertDismissed")
}

@MainActor
final class VerificationMailManager: ObservableObject {
    static let shared = VerificationMailManager()

    @Published private(set) var current: VerificationAlert?

    let displayDuration: TimeInterval = 10
    private let pollInterval: TimeInterval = 8
    private let lookback: TimeInterval = 120
    private let mailBundleID = "com.apple.mail"

    private var seenIDs = Set<String>()
    private var pollTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var primed = false

    private init() {}

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 8))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func dismiss() {
        dismissTask?.cancel()
        guard current != nil else { return }
        current = nil
        NotificationCenter.default.post(name: .verificationAlertDismissed, object: nil)
    }

    func copyCurrentCode() {
        guard case .code(let code)? = current?.payload else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    func openCurrentLink() {
        guard case .magicLink(let url)? = current?.payload else { return }
        let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        if let safari {
            NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: .init())
        } else {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }

    func present(_ alert: VerificationAlert) {
        current = alert
        NotificationCenter.default.post(name: .verificationAlertArrived, object: nil)
        dismissTask?.cancel()
        dismissTask = Task { [weak self, displayDuration] in
            try? await Task.sleep(for: .seconds(displayDuration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func poll() async {
        guard Defaults[.showVerificationCodes],
              NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleID).isEmpty == false
        else { return }

        guard let descriptor = try? await AppleScriptHelper.execute(Self.script(lookback: Int(lookback))),
              let raw = descriptor.stringValue
        else { return }

        let messages = Self.parse(raw)
        // First successful poll only records what's already there, so launching
        // the app doesn't replay codes from the last two minutes.
        defer { primed = true }
        for message in messages where !seenIDs.contains(message.id) {
            seenIDs.insert(message.id)
            guard primed else { continue }
            if let alert = VerificationCodeDetector.detect(
                id: message.id, senderRaw: message.sender, subject: message.subject, body: message.body
            ) {
                present(alert)
            }
        }
        if seenIDs.count > 500 { seenIDs = Set(messages.map(\.id)) }
    }

    private struct RawMessage {
        let id: String, sender: String, subject: String, body: String
    }

    private static let fieldSep = "\u{1E}"
    private static let recordSep = "\u{1D}"

    private static func parse(_ raw: String) -> [RawMessage] {
        raw.components(separatedBy: recordSep).compactMap { record in
            let f = record.components(separatedBy: fieldSep)
            guard f.count >= 4, !f[0].isEmpty else { return nil }
            return RawMessage(id: f[0], sender: f[1], subject: f[2], body: f[3...].joined(separator: " "))
        }
    }

    private static func script(lookback: Int) -> String {
        """
        tell application id "com.apple.mail"
            set fs to character id 30
            set rs to character id 29
            set out to ""
            set cutoff to (current date) - \(lookback)
            set recent to (messages of inbox whose date received > cutoff)
            repeat with m in recent
                set msgBody to ""
                try
                    set msgBody to content of m
                end try
                if (length of msgBody) > 4000 then set msgBody to text 1 thru 4000 of msgBody
                set out to out & (message id of m) & fs & (sender of m) & fs & (subject of m) & fs & msgBody & rs
            end repeat
            return out
        end tell
        """
    }
}
