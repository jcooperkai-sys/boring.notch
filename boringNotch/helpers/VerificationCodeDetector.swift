//
//  VerificationCodeDetector.swift
//  boringNotch
//

import Foundation

struct VerificationAlert: Equatable, Identifiable {
    enum Payload: Equatable {
        case code(String)
        case magicLink(URL)
    }

    let id: String
    let sender: String
    let payload: Payload
}

enum VerificationCodeDetector {
    private static let triggerPhrases = [
        "verification code", "verify", "verification", "one-time", "one time",
        "otp", "passcode", "security code", "login code", "sign in", "sign-in",
        "signin", "log in", "login", "confirm", "2fa", "two-factor", "code",
    ]

    private static let marketingPhrases = [
        "promo code", "discount code", "coupon", "% off", "gift code", "referral code",
    ]

    private static let linkPhrases = [
        "sign in", "sign-in", "log in", "login", "magic link", "verify",
        "confirm", "continue", "authenticate",
    ]

    private static let linkPathHints = [
        "magic", "signin", "sign-in", "sign_in", "login", "log-in", "verify",
        "confirm", "auth", "token", "callback", "otp",
    ]

    // Words that look like codes but aren't (years, common filler) are filtered below.
    private static let codeRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9\-/.#])(?=[A-Z0-9-]*\d)([A-Z0-9]{3}-[A-Z0-9]{3}|[A-Z0-9]{4,8})(?![A-Za-z0-9\-/.])"#
    )

    private static let urlDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func detect(id: String, senderRaw: String, subject: String, body: String) -> VerificationAlert? {
        let haystack = "\(subject)\n\(body)"
        let lower = haystack.lowercased()
        guard triggerPhrases.contains(where: lower.contains) else { return nil }
        guard !marketingPhrases.contains(where: lower.contains) else { return nil }

        let sender = displaySender(senderRaw)
        if let code = extractCode(subject: subject, body: body) {
            return VerificationAlert(id: id, sender: sender, payload: .code(code))
        }
        if linkPhrases.contains(where: lower.contains), let url = extractMagicLink(body) {
            return VerificationAlert(id: id, sender: sender, payload: .magicLink(url))
        }
        return nil
    }

    static func extractCode(subject: String, body: String) -> String? {
        // Subject first: "123456 is your Roblox code" is the most reliable spot.
        for raw in [subject, String(body.prefix(4000))] {
            // Google prefixes codes as "G-123456"; show just the digits.
            let text = raw.replacingOccurrences(of: #"\bG-(\d{4,8})\b"#, with: "$1", options: .regularExpression)
            let range = NSRange(text.startIndex..., in: text)
            let candidates = codeRegex.matches(in: text, range: range).compactMap { match -> String? in
                guard let r = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[r])
            }
            if let best = candidates.first(where: isPlausibleCode) {
                return best
            }
        }
        return nil
    }

    private static func isPlausibleCode(_ candidate: String) -> Bool {
        let digits = candidate.filter(\.isNumber)
        if digits.count == candidate.filter({ $0 != "-" }).count {
            // Pure digits: reject years and 3-or-fewer digit strings.
            if candidate.count == 4, let n = Int(candidate), (1900...2100).contains(n) { return false }
            return candidate.filter(\.isNumber).count >= 4
        }
        // Alphanumeric: needs at least two digits so words like "A1RT" from noise don't win.
        return digits.count >= 2
    }

    static func extractMagicLink(_ body: String) -> URL? {
        let range = NSRange(body.startIndex..., in: body)
        let urls = urlDetector.matches(in: body, range: range).compactMap(\.url)
            .filter { $0.scheme == "https" }
        return urls.first { url in
            let s = url.absoluteString.lowercased()
            return linkPathHints.contains(where: s.contains)
                && !s.contains("unsubscribe") && !s.contains("privacy")
        }
    }

    /// `"Roblox" <noreply@roblox.com>` -> `Roblox`; `noreply@accounts.google.com` -> `Google`.
    static func displaySender(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lt = trimmed.firstIndex(of: "<") {
            let name = trimmed[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !name.isEmpty { return name }
        }
        let address = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard let at = address.firstIndex(of: "@") else { return trimmed }
        let parts = address[address.index(after: at)...].split(separator: ".")
        let domain = parts.count >= 2 ? parts[parts.count - 2] : parts.first ?? ""
        return domain.prefix(1).uppercased() + domain.dropFirst()
    }
}
