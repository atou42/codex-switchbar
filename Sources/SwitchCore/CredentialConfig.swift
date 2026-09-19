import Foundation

/// Deliberately NOT a TOML rewriter. Only recognizes a simple, unambiguous top-level
/// setting. Complex/quoted/multiline forms fail closed and can be edited by the user.
public enum CredentialConfig {
    public enum Mode: Equatable { case file, other(String), missing, ambiguous }
    public static func inspect(_ text: String) -> Mode {
        var matches: [String] = []
        var root = true
        let pattern = #"^\s*cli_auth_credentials_store\s*=\s*["'](file|keyring|auto|ephemeral)["']\s*(?:#.*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return .ambiguous }
        for original in text.components(separatedBy: .newlines) {
            let line = original.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // Multiline TOML cannot be safely interpreted by a single-setting reader.
            if line.contains("\"\"\"") || line.contains("'''") { return .ambiguous }
            if line.hasPrefix("[") { root = false }
            if root && line.contains("cli_auth_credentials_store") {
                let range = NSRange(original.startIndex..<original.endIndex, in: original)
                guard let match = regex.firstMatch(in: original, range: range),
                      let valueRange = Range(match.range(at: 1), in: original) else { return .ambiguous }
                matches.append(String(original[valueRange]))
            }
        }
        if matches.count > 1 { return .ambiguous }
        guard let mode = matches.first else { return .missing }
        return mode == "file" ? .file : .other(mode)
    }
    public static func inspect(url: URL) throws -> Mode {
        guard let data = try SecureFile.read(url), let text = String(data: data, encoding: .utf8) else {
            return .missing
        }
        return inspect(text)
    }
    /// Consent is collected in the UI. Existing non-file modes are never migrated.
    @discardableResult public static func enableFileMode(url: URL) throws -> URL? {
        let old = try SecureFile.read(url)
        let mode: Mode
        if let old {
            guard let text = String(data: old, encoding: .utf8) else { throw SwitchError.configurationAmbiguous }
            mode = inspect(text)
        } else { mode = .missing }
        switch mode {
        case .file: return nil
        case .other: throw SwitchError.fileStoreRequired
        case .ambiguous: throw SwitchError.configurationAmbiguous
        case .missing: break
        }
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("config.before-codex-switch.\(UUID().uuidString).toml")
        if let old { try SecureFile.write(old, to: backup) }
        var next = Data("# Credential storage for Codex Switch (shared by all accounts).\ncli_auth_credentials_store = \"file\"\n\n".utf8)
        if let old { next.append(old) }
        try SecureFile.write(next, to: url, expected: old, compare: true)
        return old == nil ? nil : backup
    }
}
