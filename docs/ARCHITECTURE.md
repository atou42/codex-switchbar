# Implementation notes

## Design choice

Native SwiftUI `MenuBarExtra` + one small settings window. One Swift Package, no external packages, no Node/Electron/Tauri runtime, no background daemon, no custom OAuth implementation. The important complexity is credential lifecycle and truthful UI states, not adding many providers.

`Sources/SwitchCore` holds testable identity, files, account operations, usage models, and stdio RPC. `Sources/CodexSwitchbar` contains macOS SwiftUI, the actor-isolated view model, preferences, and a debounced directory watcher. `Security.framework` and `ServiceManagement` are platform APIs, not third-party dependencies.

## Account state

The active account is derived from `auth.json` identity, never the last button pressed. Identity combines workspace ID and user principal. Token bytes are retained unchanged (including unrecognized future fields). Labels never form filesystem paths; UUIDs identify Keychain records. A watched directory handles atomic file replacements, with a thirty-second local polling fallback. Observation refreshes known credentials, but does not silently import every unknown login.

A normal switch is:

1. Verify the shared file credential mode, app lock, absent recovery marker, and no Codex processes.
2. Read and save the outgoing live blob to Keychain, including its latest refreshed token.
3. Read the target and compare its identity to its saved record.
4. Write a token-free journal, recheck process state and live file bytes.
5. Atomically replace the active file with a 0600 target, re-read identity, and reconcile the latest actual bytes.
6. Remove the completed journal. Refresh the active-account UI and request its usage.

If a process appears before any live write, the marker is removed and the explicit request remains queued. If a file changes or an error happens after a possible write, the marker remains for explicit recovery. Recovery reconciles the actual file; it never automatically replays a stale backup. Config, history, sessions, skills, and MCP files are not modified by switching.

Queues are in-memory, tied to the observed starting identity, cancellable, and expire after five minutes. A changed identity cancels the queue rather than unexpectedly applying it later. A running process is treated as busy even if no model task is visible. This is intentionally conservative.

## Official RPC boundary

The app starts the installed executable with `-s read-only -a never app-server`, the existing shared home, and no token arguments. No model turns are requested, and server-initiated tool requests are rejected. Calls are serialized on a background worker:

- `initialize`, followed by the `initialized` notification;
- `account/read` with `refreshToken: false` to verify the visible account;
- `account/rateLimits/read` for quota;
- or `account/login/start` with `type: chatgpt`, followed by `account/login/completed`.

Successful login keeps the resulting account active, preserving the previous account in the vault. Reusing a known browser account does not overwrite its name. Cancellation preserves whatever valid live login remains; it does not call global logout or overwrite a potentially refreshed credential with an old snapshot.

Requests have IDs, bounded buffering, generic redacted errors, and monotonic deadlines. Early notifications are buffered. Cancellation stops only our helper. A second operation waits until its helper has closed. App shutdown cancels and awaits its operation before terminating. No official backend is modified or vendored.

Do not add a raw HTTP endpoint as a fallback for a failed quota read: maintain the official RPC adapter or show unavailable. A slow result is stored only if the live identity still matches its captured account. This check prevents a common late-response misattribution, but is not proof against arbitrary external ABA identity changes.

## Usage truthfulness

A quota snapshot has its own fetch time. Windows are optional, durations are dynamic, and percentages are `100 - usedPercent`, clamped to a valid range. Credits and reset-credit counts are separate fields. Missing fields remain unknown. At the reported reset time, the view says it needs a refresh instead of making up a new balance. Inactive-account cache is always labeled. UI timers update countdowns, not balances.

Automatic active reads are five minutes apart; manual reads are throttled to fifteen seconds. The menu does not launch a usage process while a switch is pending, and a switch request cancels an in-flight read before attempting the file change. We do not rotate credentials to refresh the account list.

## Persistence & maintenance map

- `Credentials.swift`: local metadata extraction; change only with synthetic fixtures for new official schemas.
- `AccountStore.swift`: operations/journal/versioned index; preserve failure ordering.
- `SecureFile.swift`: permissions, no-follow file access, comparison and atomic replacement, own-process advisory lock.
- `Vault.swift`: macOS Keychain implementation; tests inject an in-memory vault.
- `CredentialConfig.swift`: conservative, byte-preserving opt-in; not a full TOML rewriter.
- `ProcessSafety.swift`: executable discovery and best-effort process-name detection. Verify this when supporting new Codex client packaging.
- `AppServerClient.swift`: the only subprocess protocol adapter. Do not log payloads.
- `Usage.swift`: optional data and decoding; tolerate unknown fields.
- `AppModel.swift`: UI lifecycle, explicit queue, official login and usage workers.
- `Presentation.swift` / views: formatting and native interface; no credential logic.

The app lock is not a lock honored by Codex. Atomic replacement avoids partial reads, not every logical race. These distinctions must survive future refactors. See SECURITY.md for the threat model, and VALIDATION.md before describing the app as tested on a Mac.

## Provider selection (0.2.0)

`AccountProvider` routes local control commands, defaulting missing provider fields to Codex for compatibility. GUI selection controls which provider's panel is visible; it does not change credentials. The Codex store and RPC remain separate and unchanged. `AntigravityModel` owns the new provider's UI and control actions, using `AntigravityStore` for metadata/journals and an injected `AntigravityLiveLogin` for native storage. Registry and Keychain namespaces are distinct. Unsupported provider operations fail explicitly.

Antigravity login deliberately uses the official interactive CLI in Terminal. The app records a pending login, opens `agy`, and waits for the user to finish authentication and exit agy before `finish` saves the result. The journal survives app restarts. `cancel` reconciles a resulting login or leaves a missing login missing; it never resurrects stale credentials. Existing-account login does not rename that account. Switches fail while Antigravity processes run; there is no background rotation, silent retry, or forced termination.

### Antigravity usage and compact label

`AntigravityUsageClient` gates the official read-only print report by version, bounds the subprocess and strictly validates the zero-turn result. `AntigravityStore.storeUsage` verifies live identity before updating metadata. A cancellable background task keeps the UI responsive, throttles manual reads to 15 seconds and automatic reads to five minutes, and prevents same-provider mutations during a read. Inactive accounts retain dated caches. The selected Gemini or Other models (Claude and GPT-OSS) quota group is a local display preference. Two menu-bar rows independently expire at the 5h and weekly reset times, without inventing a full balance.

## Explicit saved-account Codex usage

`SavedUsageClient` creates a private disposable worker home and uses experimental external-token login with ephemeral storage. `AccountStore.savedUsageCredentials` verifies the saved identity; `storeSavedUsage` binds results to the exact captured credential and account ID, rejects stale or changed records, and writes only the registry usage. The normal active-account path retains its live-identity gate. The UI serializes requests with other Codex operations and throttles manual lookups per account to 15 seconds. `usage NAME_OR_ID` selects this path; no selector retains active-account behavior. No permanent account workspace or refresh-token worker is created.
