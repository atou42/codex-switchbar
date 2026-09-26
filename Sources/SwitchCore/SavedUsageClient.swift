import Foundation
import CoreFoundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

public enum SavedUsageError: Error, LocalizedError, Equatable {
    case invalidAccessToken, expiredCredentials, identityMismatch, cleanupFailed
    public var errorDescription: String? {
        switch self {
        case .invalidAccessToken: return "This saved login cannot be used for a separate balance check. Sign in again."
        case .expiredCredentials: return "This saved login has expired. Sign in again to refresh its balance."
        case .identityMismatch: return "The saved login and returned account do not match. The cache was not changed."
        case .cleanupFailed: return "The temporary balance-check directory could not be removed."
        }
    }
}

/// An explicitly requested, read-only external-token RPC. No credential file or
/// refresh token is passed to the helper; the user's shared home is never opened.
public enum SavedUsageClient {
    public static func read(executable: URL, credential: Credentials,
                            cancellation: CancellationFlag = CancellationFlag()) throws -> UsageSnapshot {
        if cancellation.isCancelled { throw SwitchError.cancelled }
        let token = try accessToken(credential, now: Date())
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-switch-usage-\(UUID().uuidString)")
        guard mkdir(home.path, 0o700) == 0 else { throw SwitchError.fileIO }
        let result: Result<UsageSnapshot, Error>
        do {
            result = .success(try query(executable: executable, credential: credential,
                                        token: token, home: home, cancellation: cancellation))
        } catch { result = .failure(error) }
        // query closes the helper before cleanup, including failed authentication.
        // Cleanup is part of success, and errors never silently leave a directory.
        do { try FileManager.default.removeItem(at: home) }
        catch { throw SavedUsageError.cleanupFailed }
        return try result.get()
    }

    private static func query(executable: URL, credential: Credentials, token: String,
                              home: URL, cancellation: CancellationFlag) throws -> UsageSnapshot {
        let client = try AppServerClient(executable: executable, home: home,
                                        cancellation: cancellation, isolatedExternalAuth: true)
        defer { client.close() }
        try client.initialize(experimental: true)
        let login = try client.request("account/login/start", params: [
            "type": "chatgptAuthTokens", "accessToken": token,
            "chatgptAccountId": credential.identity.workspace
        ])
        guard login["type"] as? String == "chatgptAuthTokens" else {
            throw SwitchError.rpc("account/login/start")
        }
        let account = try client.request("account/read", params: ["refreshToken": false])
        guard let details = account["account"] as? [String: Any],
              details["type"] as? String == "chatgpt" else { throw SavedUsageError.identityMismatch }
        // External auth has no ID token; the optional email can be absent even
        // when its access-token workspace and principal were verified above.
        if let expected = credential.email, let email = details["email"] as? String, !email.isEmpty {
            guard email.caseInsensitiveCompare(expected) == .orderedSame else { throw SavedUsageError.identityMismatch }
        }
        let usage = try client.request("account/rateLimits/read")
        return try UsageSnapshot.parse(JSONSerialization.data(withJSONObject: usage))
    }

    /// Local routing checks are not cryptographic verification; official RPC
    /// verifies the supplied access token. Expired tokens are never refreshed here.
    static func accessToken(_ credential: Credentials, now: Date) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: credential.raw) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, token.count <= 131_072 else {
            throw SavedUsageError.invalidAccessToken
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw SavedUsageError.invalidAccessToken }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = claims["exp"] as? NSNumber,
              CFGetTypeID(expiry) != CFBooleanGetTypeID(), expiry.doubleValue.isFinite else {
            throw SavedUsageError.invalidAccessToken
        }
        guard expiry.doubleValue > now.timeIntervalSince1970 else { throw SavedUsageError.expiredCredentials }
        guard let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let workspace = auth["chatgpt_account_id"] as? String,
              workspace == credential.identity.workspace else { throw SavedUsageError.identityMismatch }
        let user = auth["chatgpt_user_id"] as? String ?? claims["sub"] as? String
        guard let user, !user.isEmpty, "id:\(user)" == credential.identity.principal else {
            throw SavedUsageError.identityMismatch
        }
        return token
    }
}
