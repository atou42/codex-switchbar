import Foundation

/// Intentionally fixed messages: never attach raw OAuth, RPC, or subprocess output.
public enum SwitchError: Error, LocalizedError, Equatable {
    case invalidCredentials, unsupportedAuth, missingIdentity, missingCredentials
    case invalidName, accountNotFound, identityMismatch, concurrentChange
    case unsafePath, fileIO, locked, unsupportedSchema, corruptRegistry
    case fileStoreRequired, configurationAmbiguous, runningClients(Int)
    case keychain(Int32), rpc(String), timeout, cancelled, processFailed, responseTooLarge
    case untrustedLoginURL, executableMissing, unfinishedTransaction

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Credentials are incomplete or not valid JSON."
        case .unsupportedAuth: return "Only ChatGPT OAuth accounts are supported; API keys are not imported."
        case .missingIdentity: return "Cannot distinguish this user's identity and workspace safely."
        case .missingCredentials: return "No file-based Codex login was found."
        case .invalidName: return "Use a name of 1–32 characters without control characters."
        case .accountNotFound: return "The saved account was not found."
        case .identityMismatch: return "The saved credential does not match its account. Nothing was switched."
        case .concurrentChange: return "Another program changed the login during this operation. Please retry."
        case .unsafePath: return "A credential or storage path is a symlink, has an unexpected owner, or is not a regular file."
        case .fileIO: return "A protected local file could not be read or written."
        case .locked: return "Another Codex Switch instance is using the account store."
        case .unsupportedSchema: return "This account store was created by a newer version."
        case .corruptRegistry: return "The account index cannot be read. It was not replaced."
        case .fileStoreRequired: return "Set the shared Codex config's cli_auth_credentials_store to file first."
        case .configurationAmbiguous: return "The credential-store setting is ambiguous. Edit config.toml manually."
        case .runningClients(let count): return "Close the \(count) detected Codex process(es) before switching."
        case .keychain(let code): return "macOS Keychain is unavailable (status \(code)). Credentials were not switched."
        case .rpc(let method): return "Codex could not complete \(method). Open the official client to check your login."
        case .timeout: return "The official Codex helper timed out. Cached usage is unchanged."
        case .cancelled: return "Operation cancelled."
        case .processFailed: return "The local helper or process check failed. Switching was blocked for safety."
        case .responseTooLarge: return "Codex returned an unexpectedly large response."
        case .untrustedLoginURL: return "Codex returned an unexpected login URL. It was not opened."
        case .executableMissing: return "Select your installed official Codex executable in Settings."
        case .unfinishedTransaction: return "An interrupted operation needs review before another switch."
        }
    }
}
