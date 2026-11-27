import Foundation

/// Billing-relevant numbers of one API response, as found in a transcript's `usage` object.
struct RequestUsage: Equatable {
    var input = 0
    var output = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0
    var webSearches = 0
    var fast = false
    var usOnly = false

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    var tokens: Int { input + output + cacheWrite + cacheRead }
    /// Everything that was sent to the model, cached or not.
    var promptTokens: Int { input + cacheWrite + cacheRead }

    /// One message can appear on several transcript lines with growing numbers: keep the highest.
    func merged(with other: RequestUsage) -> RequestUsage {
        RequestUsage(input: max(input, other.input), output: max(output, other.output),
                     cacheWrite5m: max(cacheWrite5m, other.cacheWrite5m),
                     cacheWrite1h: max(cacheWrite1h, other.cacheWrite1h),
                     cacheRead: max(cacheRead, other.cacheRead), webSearches: max(webSearches, other.webSearches),
                     fast: fast || other.fast, usOnly: usOnly || other.usOnly)
    }
}

/// Anthropic API list prices in USD, used to estimate what the same usage would cost without a subscription.
/// Source: https://platform.claude.com/docs/en/about-claude/pricing (checked 2026-11-27).
/// The app never goes online, so new models and price changes have to be added here.
enum Pricing {
    /// USD per million tokens
    struct Rates {
        let input, cacheWrite5m, cacheWrite1h, cacheRead, output: Double

        init(_ input: Double, _ cacheWrite5m: Double, _ cacheWrite1h: Double, _ cacheRead: Double, _ output: Double) {
            self.input = input
            self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h
            self.cacheRead = cacheRead
            self.output = output
        }
    }

    //                     input  write 5m  write 1h  read  output
    private static let rates: [String: Rates] = [
        "claude-fable-5-2": Rates(8, 10, 16, 0.20, 40),
        "claude-mythos-5-2": Rates(8, 10, 16, 0.20, 40),
        "claude-fable-5-1": Rates(10, 12.50, 20, 0.25, 50),
        "claude-mythos-5-1": Rates(10, 12.50, 20, 0.25, 50),
        "claude-fable-5": Rates(10, 12.50, 20, 1, 50),
        "claude-mythos-5": Rates(10, 12.50, 20, 1, 50),
        "claude-opus-5-5": Rates(4, 5, 8, 0.20, 20),
        "claude-opus-5": Rates(5, 6.25, 10, 0.50, 25),
        "claude-opus-4-8": Rates(5, 6.25, 10, 0.50, 25),
        "claude-opus-4-7": Rates(5, 6.25, 10, 0.50, 25),
        "claude-opus-4-6": Rates(5, 6.25, 10, 0.50, 25),
        "claude-opus-4-5": Rates(5, 6.25, 10, 0.50, 25),
        "claude-opus-4-1": Rates(15, 18.75, 30, 1.50, 75),
        "claude-opus-4": Rates(15, 18.75, 30, 1.50, 75),
        "claude-sonnet-5-5": Rates(2, 2.50, 4, 0.10, 10),
        "claude-sonnet-5": Rates(2, 2.50, 4, 0.20, 10),
        "claude-sonnet-4-6": Rates(3, 3.75, 6, 0.30, 15),
        "claude-sonnet-4-5": Rates(3, 3.75, 6, 0.30, 15),
        "claude-sonnet-4": Rates(3, 3.75, 6, 0.30, 15),
        "claude-haiku-5-5": Rates(0.10, 0.125, 0.20, 0.01, 0.50),
        "claude-haiku-4-5": Rates(1, 1.25, 2, 0.10, 5),
    ]

    /// Haiku 5.5 requests with a longer prompt than this are billed at five times the price.
    private static let haikuLongPrompt = 100_000
    private static let fastModels: Set<String> = [
        "claude-fable-5-2", "claude-mythos-5-2", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8",
    ]
    private static let webSearchPrice = 0.01

    /// Price of one response in USD, or nil if the model is not in the price list.
    static func cost(model: String, usage u: RequestUsage) -> Double? {
        // claude-haiku-4-5-20251001 → claude-haiku-4-5
        let id = model.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        guard let r = rates[id] else { return nil }

        var factor = 1.0
        if id == "claude-haiku-5-5", u.promptTokens > haikuLongPrompt { factor *= 5 }
        if u.fast, fastModels.contains(id) { factor *= 2 }
        if u.usOnly { factor *= 1.1 }

        let perMillion = Double(u.input) * r.input + Double(u.cacheWrite5m) * r.cacheWrite5m
            + Double(u.cacheWrite1h) * r.cacheWrite1h + Double(u.cacheRead) * r.cacheRead
            + Double(u.output) * r.output
        return perMillion / 1_000_000 * factor + Double(u.webSearches) * webSearchPrice
    }
}
