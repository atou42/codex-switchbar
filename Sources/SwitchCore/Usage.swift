import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double?
    public var windowDurationMins: Int?
    public var resetsAt: Double?
    public init(usedPercent: Double? = nil, windowDurationMins: Int? = nil, resetsAt: Double? = nil) {
        self.usedPercent = usedPercent; self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
    public var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
    /// Reject unusable dates rather than overflowing a UI integer or inventing a countdown.
    public var validResetTimestamp: Double? {
        guard let resetsAt, resetsAt.isFinite, resetsAt > 0, resetsAt < 253_402_300_800 else { return nil }
        return resetsAt
    }
    public func resetIsPast(at now: Date) -> Bool {
        guard let timestamp = validResetTimestamp else { return false }
        return timestamp <= now.timeIntervalSince1970
    }
}

public struct CreditBalance: Codable, Equatable, Sendable {
    public var hasCredits: Bool?
    public var unlimited: Bool?
    public var balance: String?
    public init(hasCredits: Bool? = nil, unlimited: Bool? = nil, balance: String? = nil) {
        self.hasCredits = hasCredits; self.unlimited = unlimited; self.balance = balance
    }
    enum CodingKeys: String, CodingKey { case hasCredits, unlimited, balance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try c.decodeIfPresent(Bool.self, forKey: .hasCredits)
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited)
        if let text = try? c.decode(String.self, forKey: .balance) { balance = text }
        else if let number = try? c.decode(Double.self, forKey: .balance), number.isFinite { balance = String(number) }
        else { balance = nil }
    }
}

public struct UsageBucket: Codable, Equatable, Identifiable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var primary: UsageWindow?
    public var secondary: UsageWindow?
    public var credits: CreditBalance?
    public var planType: String?
    public var id: String { limitId ?? "codex" }
    public init(limitId: String? = "codex", limitName: String? = nil,
                primary: UsageWindow? = nil, secondary: UsageWindow? = nil,
                credits: CreditBalance? = nil, planType: String? = nil) {
        self.limitId = limitId; self.limitName = limitName
        self.primary = primary; self.secondary = secondary
        self.credits = credits; self.planType = planType
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    public var buckets: [UsageBucket]
    public var availableResetCredits: Int?
    public init(fetchedAt: Date = Date(), buckets: [UsageBucket], availableResetCredits: Int? = nil) {
        self.fetchedAt = fetchedAt; self.buckets = buckets; self.availableResetCredits = availableResetCredits
    }
    public var main: UsageBucket? { buckets.first(where: { $0.id == "codex" }) ?? buckets.first }
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > 600 || now < fetchedAt || buckets.contains {
            ($0.primary?.resetIsPast(at: now) ?? false) || ($0.secondary?.resetIsPast(at: now) ?? false)
        }
    }
    /// Decode only documented app-server fields, tolerate unknown future fields.
    public static func parse(_ data: Data, at date: Date = Date()) throws -> UsageSnapshot {
        struct ResetCredits: Decodable { var availableCount: Int? }
        struct Response: Decodable {
            var rateLimits: UsageBucket?
            var rateLimitsByLimitId: [String: UsageBucket]?
            var rateLimitResetCredits: ResetCredits?
        }
        let result: Response
        do { result = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw SwitchError.rpc("account/rateLimits/read") }
        var buckets: [UsageBucket] = []
        if let map = result.rateLimitsByLimitId, !map.isEmpty {
            for key in map.keys.sorted() {
                guard var bucket = map[key] else { continue }
                bucket.limitId = key
                buckets.append(bucket)
            }
        } else if let legacy = result.rateLimits { buckets = [legacy] }
        guard !buckets.isEmpty else { throw SwitchError.rpc("account/rateLimits/read") }
        let count = result.rateLimitResetCredits?.availableCount
        return UsageSnapshot(fetchedAt: date, buckets: buckets,
                             availableResetCredits: count.flatMap { $0 >= 0 ? $0 : nil })
    }
}
